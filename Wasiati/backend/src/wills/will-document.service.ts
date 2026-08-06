import { Injectable } from '@nestjs/common';
import { readFileSync } from 'fs';
import { join } from 'path';
import { createHash } from 'crypto';
import { PdfRendererService } from '../common/pdf/pdf-renderer.service';
import { shareBasis } from './share-basis';

/**
 * Document fonts are EMBEDDED rather than relied upon from the host: a production
 * Linux container ships none of the design's faces, so the document would silently
 * print in a fallback font (or tofu, for the Arabic). Each file is read once,
 * cached, and base64-inlined into @font-face so the PDF is byte-identical on any
 * machine. The .ttf files are the same ones the Flutter app bundles — one design,
 * one set of faces (DV2.1: Fraunces display / Public Sans body / IBM Plex Sans
 * Arabic in AR / Amiri for the bismillah).
 */
const fontCache = new Map<string, string>();
function fontBase64(file: string): string {
  const cached = fontCache.get(file);
  if (cached !== undefined) return cached;
  const candidates = [
    join(__dirname, '../../assets/fonts', file), // dist/ → repo root
    join(process.cwd(), 'assets/fonts', file),
  ];
  for (const p of candidates) {
    try {
      const b64 = readFileSync(p).toString('base64');
      fontCache.set(file, b64);
      return b64;
    } catch {
      // try next
    }
  }
  fontCache.set(file, ''); // degrade to host fonts rather than failing the export
  return '';
}

function fontFace(family: string, file: string, weight = '400'): string {
  const b64 = fontBase64(file);
  if (!b64) return '';
  return `@font-face {
    font-family: "${family}";
    src: url(data:font/ttf;base64,${b64}) format("truetype");
    font-weight: ${weight};
    font-style: normal;
    font-display: block;
  }`;
}

/**
 * Renders a will to a print-ready PDF.
 *
 * The HTML is built here; PdfRendererService owns the (shared, lazily launched)
 * headless Chromium that prints it — see that service for why Chromium and not a
 * PDF library.
 */
@Injectable()
export class WillDocumentService {
  constructor(private pdf: PdfRendererService) {}

  /**
   * @param opts.format  'table' (structured estate listing) or 'essay' (the estate
   *                     inventory as narrative will language — DV2.1's "ESTATE
   *                     FORMAT" toggle changes how the assets & loans READ; the
   *                     rest of the document keeps its structure in both).
   * @param opts.lang    'en' or 'ar' (full RTL, Arabic-Indic numerals).
   * @param opts.display 'percent' (default) or 'fraction' — fara'id shares as
   *                     their fraction over the classical denominators (1/8, 7/12,
   *                     7/24 …); shares without a clean fraction fall back to %.
   */
  async renderPdf(will: WillDocumentData, opts: WillDocumentOptions = {}): Promise<Buffer> {
    const format = opts.format ?? 'table';
    const lang = opts.lang ?? 'en';
    const display = opts.display ?? 'percent';
    // Tighter margins than the renderer default: the page is a wash on which the
    // bordered parchment sheet floats (see .sheet in buildHtml), so the print
    // margin is only the wash gutter around the card — the card's own 44/46px
    // padding does the real inset, exactly as in the prototype.
    return this.pdf.render(buildHtml(will, format, lang, display), {
      margin: { top: '12mm', bottom: '12mm', left: '12mm', right: '12mm' },
    });
  }
}

export interface WillDocumentData {
  id: string;
  ownerEmail: string;
  tier: string;
  status: string;
  sealedAt?: Date | null;
  signedAt?: Date | null;
  signedIp?: string | null;
  disclaimerVersion?: string | null;
  disclaimerAcceptedAt?: Date | null;
  personalMessage?: string | null;
  /**
   * Testator's registered city and ISO-3166 country, from the owner's profile
   * address — the header's "of {name} — {city, country}" line. Optional: a
   * profile without an address simply omits the place.
   */
  testatorCity?: string | null;
  testatorCountry?: string | null;
  /**
   * Funeral & burial wishes (spec §8: wishes{sunnah,simple,local,azaa}). Null or
   * absent (the owner never answered) → no wishes section at all.
   */
  funeralWishes?: unknown;
  /**
   * Guardianship of minor children, as chosen in create-flow step 3 and stored on
   * the Will row. 'parent' (the surviving parent), 'islamic' (the order of
   * guardianship under the testator's school) or 'named' (guardianName + contact).
   * Null/absent on a will where the owner never answered — that will renders NO
   * guardianship section at all (see guardianOf).
   */
  guardianMode?: string | null;
  guardianName?: string | null;
  guardianPhone?: string | null;
  guardianEmail?: string | null;
  /** Estate inventory. `type === 'LIABILITY'` is a debt; everything else is an asset. */
  assets?: {
    type: string;
    label: string;
    institution?: string | null;
    estimatedValue?: unknown;
    currency?: string | null;
  }[];
  /**
   * basisEn/basisAr: the scriptural basis line under each heir (findOne attaches
   * them). Optional — derived from the relation via shareBasis() when absent, so
   * the document never shows a share without its fiqh "why".
   */
  shariaShares: {
    heirName: string;
    heirRelation: string;
    sharePercent: unknown;
    basisEn?: string;
    basisAr?: string;
  }[];
  bequests: { beneficiaryName: string; sharePercent: unknown }[];
  witnesses: {
    fullName: string;
    status: string;
    signedAt?: Date | null;
    ipAddress?: string | null;
    userAgent?: string | null;
    idMatchStatus?: string | null;
  }[];
  trustees: {
    fullName: string;
    status?: string;
    confirmedAt?: Date | null;
    ipAddress?: string | null;
    userAgent?: string | null;
    /** Shown under a pending trustee's signature line, so the family can reach them. */
    phone?: string | null;
    email?: string | null;
  }[];
}

export type WillDocumentFormat = 'table' | 'essay';
export type WillDocumentLang = 'en' | 'ar';
/** How fara'id shares are displayed: percentages or canonical fractions (spec §3 export toggle). */
export type WillDocumentDisplay = 'percent' | 'fraction';
export interface WillDocumentOptions {
  format?: WillDocumentFormat;
  lang?: WillDocumentLang;
  display?: WillDocumentDisplay;
}

/**
 * The classical asl al-mas'ala denominators, ascending — a fara'id division always
 * resolves to exact rationals over these, so nearly every share has a clean
 * fraction: 12.5 -> "1/8", 58.33 -> "7/12", 29.17 -> "7/24". Ascending order makes
 * the FIRST hit the simplest form (50 lands on 1/2, never 48/96).
 */
const ASL_DENOMINATORS = [2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 96] as const;

/**
 * Maps a share percentage to its fara'id fraction, or null when none is clean
 * (then the document falls back to the percentage). A verbatim port of the
 * prototype's fracOf (DV2.1 line 4115) — an earlier version accepted only the six
 * Qur'anic fractions, which left residue and ʿawl-scaled shares stuck as
 * percentages, so flipping the SHARES AS toggle visibly changed almost nothing
 * ("fraction percentage toggle isn't responding" — owner, 27 Jul 2026).
 *
 * The tolerance (0.0008 in fraction units = 0.08 pp) absorbs the 2-dp rounding of
 * repeating decimals (58.33 vs 58.333…) while staying far below the gap between
 * neighbouring candidate fractions.
 */
export function fractionLabel(percent: number): string | null {
  const n = Number(percent);
  if (!Number.isFinite(n)) return null;
  const target = n / 100;
  for (const q of ASL_DENOMINATORS) {
    const p = Math.round(target * q);
    if (p > 0 && p < q && Math.abs(target - p / q) < 0.0008) return `${p}/${q}`;
  }
  return null;
}

/** Escapes text for safe interpolation — the will contains user-supplied names. */
function esc(s: unknown): string {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

const RELATION_LABEL: Record<string, string> = {
  HUSBAND: 'Husband',
  WIFE: 'Wife',
  SON: 'Son',
  DAUGHTER: 'Daughter',
  SON_SON: "Son's son",
  SON_DAUGHTER: "Son's daughter",
  FATHER: 'Father',
  MOTHER: 'Mother',
  GRANDFATHER: 'Grandfather (paternal)',
  PATERNAL_GRANDMOTHER: 'Grandmother (paternal)',
  MATERNAL_GRANDMOTHER: 'Grandmother (maternal)',
  GRANDMOTHER: 'Grandmother',
  FULL_BROTHER: 'Brother (full)',
  FULL_SISTER: 'Sister (full)',
  CONSANGUINE_BROTHER: 'Brother (paternal half)',
  CONSANGUINE_SISTER: 'Sister (paternal half)',
  MATERNAL_SIBLING: 'Sibling (maternal half)',
  FULL_NEPHEW: "Brother's son",
  CONSANGUINE_NEPHEW: "Brother's son (paternal half)",
  FULL_UNCLE: 'Paternal uncle',
  CONSANGUINE_UNCLE: 'Paternal uncle (paternal half)',
  FULL_COUSIN: "Paternal uncle's son",
  CONSANGUINE_COUSIN: "Paternal uncle's son (paternal half)",
};

const RELATION_LABEL_AR: Record<string, string> = {
  HUSBAND: 'الزوج',
  WIFE: 'الزوجة',
  SON: 'الابن',
  DAUGHTER: 'البنت',
  SON_SON: 'ابن الابن',
  SON_DAUGHTER: 'بنت الابن',
  FATHER: 'الأب',
  MOTHER: 'الأم',
  GRANDFATHER: 'الجد (لأب)',
  PATERNAL_GRANDMOTHER: 'الجدة (لأب)',
  MATERNAL_GRANDMOTHER: 'الجدة (لأم)',
  GRANDMOTHER: 'الجدة',
  FULL_BROTHER: 'الأخ الشقيق',
  FULL_SISTER: 'الأخت الشقيقة',
  CONSANGUINE_BROTHER: 'الأخ لأب',
  CONSANGUINE_SISTER: 'الأخت لأب',
  MATERNAL_SIBLING: 'الأخ/الأخت لأم',
  FULL_NEPHEW: 'ابن الأخ الشقيق',
  CONSANGUINE_NEPHEW: 'ابن الأخ لأب',
  FULL_UNCLE: 'العم الشقيق',
  CONSANGUINE_UNCLE: 'العم لأب',
  FULL_COUSIN: 'ابن العم الشقيق',
  CONSANGUINE_COUSIN: 'ابن العم لأب',
  BAYT_AL_MAL: 'بيت المال',
};

const RELATION_LABEL_BAYT_EN = 'Public treasury (bayt al-māl)';

function relationLabel(relation: string, lang: WillDocumentLang): string {
  if (lang === 'ar') return RELATION_LABEL_AR[relation] ?? relation;
  if (relation === 'BAYT_AL_MAL') return RELATION_LABEL_BAYT_EN;
  return RELATION_LABEL[relation] ?? relation;
}

/** Western digits → Arabic-Indic (٠-٩), for the AR document. */
function toArabicDigits(s: string): string {
  return s.replace(/[0-9]/g, (d) => '٠١٢٣٤٥٦٧٨٩'[Number(d)]);
}

const pctFor = (lang: WillDocumentLang) => (v: unknown) => {
  const n = Number(v ?? 0);
  const s = `${n.toFixed(n % 1 === 0 ? 0 : 2)}%`;
  // Arabic gets Arabic-Indic digits plus the Arabic decimal separator (٫) and
  // percent sign (٪), so the whole figure reads natively.
  return lang === 'ar' ? toArabicDigits(s).replace('.', '٫').replace('%', '٪') : s;
};

/**
 * Fara'id share formatter. display='fraction' renders the share's fraction
 * (Arabic-Indic digits in AR) and falls back to the percentage for shares with
 * no clean fraction (prototype h.docShare, line 4127). Bequests always render
 * as % — the free third is user-chosen, not a fara'id fraction.
 */
const shareFor = (lang: WillDocumentLang, display: WillDocumentDisplay) => {
  const pct = pctFor(lang);
  return (v: unknown) => {
    if (display === 'fraction') {
      const f = fractionLabel(Number(v ?? 0));
      if (f) return lang === 'ar' ? toArabicDigits(f) : f;
    }
    return pct(v);
  };
};

/**
 * Money for the estate inventory: thousands separators, decimals only when the
 * value isn't whole (e.g. "SAR 184,000", "USD 1,250.50"). Arabic gets
 * Arabic-Indic digits with the Arabic thousands (٬) and decimal (٫) separators,
 * matching the rest of the AR document. A negative value is prefixed with a
 * true minus sign (−). Implemented by hand rather than toLocaleString so the
 * output does not depend on the host's ICU build.
 */
const moneyFor = (lang: WillDocumentLang) => (currency: string | null | undefined, value: unknown) => {
  const n = Number(value ?? 0);
  const abs = Math.abs(n);
  const fixed = Number.isInteger(abs) ? abs.toFixed(0) : abs.toFixed(2);
  const [int, frac] = fixed.split('.');
  let s = int.replace(/\B(?=(\d{3})+(?!\d))/g, ',') + (frac ? `.${frac}` : '');
  if (lang === 'ar') s = toArabicDigits(s).replace(/,/g, '٬').replace(/\./g, '٫');
  const amount = currency ? `${currency} ${s}` : s;
  return n < 0 ? `− ${amount}` : amount;
};

/**
 * "3 May 2026" / "٣ مايو ٢٠٢٦" — the prototype's docDate. Hand-rolled month
 * names (like moneyFor) so the output does not depend on the host's ICU build.
 */
const MONTHS_EN = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const MONTHS_AR = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];
function fmtDate(d: Date | string | null | undefined, lang: WillDocumentLang): string {
  if (!d) return '—';
  const dt = new Date(d);
  const months = lang === 'ar' ? MONTHS_AR : MONTHS_EN;
  const s = `${dt.getUTCDate()} ${months[dt.getUTCMonth()]} ${dt.getUTCFullYear()}`;
  return lang === 'ar' ? toArabicDigits(s) : s;
}

/** ISO-3166 alpha-2 → localized country name, degrading to the raw code without full ICU. */
function countryName(code: string | null | undefined, lang: WillDocumentLang): string {
  const c = (code ?? '').trim().toUpperCase();
  if (!c) return '';
  try {
    return new Intl.DisplayNames([lang === 'ar' ? 'ar' : 'en'], { type: 'region' }).of(c) ?? c;
  } catch {
    return c;
  }
}

type WillAsset = NonNullable<WillDocumentData['assets']>[number];

/**
 * Net estate per currency: sum(assets) − sum(liabilities). Items without an
 * estimated value are listed in the document but cannot enter the arithmetic.
 */
function assetTotals(items: WillAsset[]): { currency: string | null; net: number }[] {
  const totals = new Map<string, { currency: string | null; net: number }>();
  for (const it of items) {
    if (it.estimatedValue == null) continue;
    const key = it.currency ?? '';
    const entry = totals.get(key) ?? { currency: it.currency ?? null, net: 0 };
    entry.net += (it.type === 'LIABILITY' ? -1 : 1) * Number(it.estimatedValue);
    totals.set(key, entry);
  }
  return [...totals.values()];
}

/**
 * All user-facing chrome, per language. Heir names stay verbatim. The document
 * strings are the DV2.1 prototype's doc* set; the estate footnote deliberately
 * DROPS the prototype's "foreign amounts converted" sentence — regions are
 * separate databases and no FX conversion happens (schema: Asset.currency).
 */
const STRINGS: Record<WillDocumentLang, Record<string, string>> = {
  en: {
    title: 'Last Will & Testament',
    ofName: 'of {name}',
    draft: 'Draft — not yet sealed',
    willNo: 'Will #{id}',
    sealedOn: 'sealed {date}',
    witnessesConfirmed: '{n} witnesses confirmed',
    witnessConfirmedOne: '1 witness confirmed',
    wordsTitle: 'Words for my family',
    wishesTitle: 'Funeral & burial wishes',
    wish1: 'Ghusl and shrouding per the Sunnah',
    wish2: 'A simple burial — no extravagance, no delay',
    wish3: 'Bury me in the nearest Muslim cemetery',
    wish4: 'Hold an ʿazāʾ (condolence gathering) — three days, no more',
    wish4no: 'No ʿazāʾ gathering — duʿāʾ suffices',
    estateTitle: 'Assets & liabilities',
    netEstate: 'Net estate',
    estateNote:
      'Estate inventory as recorded at sealing; debts are settled before the shares are distributed.',
    divisionTitle: 'Division of the estate',
    noHeirs: 'No heirs recorded.',
    bequestRow: 'Bequest',
    bequestBasis: 'From the free third — outside the fara’id',
    witnessesTitle: 'Witnesses & trustee',
    witnessesCol: 'Witnesses',
    trusteeCol: 'Trustee',
    witnessRole: 'Witness',
    trusteeRole: 'Trustee',
    testatorRole: 'Testator',
    signedDigitally: 'Signed digitally',
    pending: 'pending',
    pendingCode: 'pending code',
    noneRecorded: 'None recorded.',
    sealLine: 'Sealed & witnessed via Wasiati',
    docDisclaimer:
      'The fara’id shares herein are computed for guidance and are not a fatwa or legal advice; the estate is divided according to the sharia (fara’id) per the school selected by the testator.',
    disclaimer:
      "Shares are computed to the fara'id. Wasiati does not provide legal advice; requirements vary by jurisdiction and this document may require witnesses or notarisation to be enforceable.",
    // Guardianship of minor children. See guardianOf() for why the 'islamic' mode
    // records the DIRECTION and deliberately does not state the order itself.
    guardianHeading: 'Guardianship of minor children',
    guardianRowLabel: 'Guardian',
    guardianColPhone: 'Phone',
    guardianColEmail: 'Email',
    guardianParentValue: 'The surviving parent',
    guardianIslamicValue: 'To be determined by the Islamic order of guardianship',
    guardianParentNote:
      "The surviving parent is to have the care of each child who is under age, and of that child's share, until they come of age.",
    guardianIslamicNote:
      'Guardianship is to be determined according to the Islamic order of guardianship applicable under the school of law recorded in this will, at the time this will takes effect. This document does not itself set out that order.',
    guardianNamedNote:
      "The person named above is appointed guardian of each child who is under age, and of that child's share, until they come of age.",
    // Narrative-format equivalents — first person, matching the estate narrative's register.
    essayGuardianParent:
      'I direct that the care of my children who are under age, and of each such child’s share, pass to their surviving parent until they come of age.',
    essayGuardianIslamic:
      'I direct that guardianship of my children who are under age, and of each such child’s share, be determined according to the Islamic order of guardianship applicable under the school of law recorded in this will, at the time this will takes effect. I do not set out that order here; it is to be established by a competent scholar or court.',
    essayGuardianNamed:
      'I appoint {name} as guardian of my children who are under age, and of each such child’s share, until they come of age.',
    essayGuardianContact: ' They may be reached at {contact}.',
    // Estate inventory as narrative will language (the "Narrative" estate format).
    // Item clauses are appended to the label only when the datum exists; items are
    // joined "a; b; and c".
    essayAssetsLead: 'I declare that, as of the sealing of this will, I own the following assets: ',
    essayLiabilitiesLead:
      'I further declare the following debts and obligations, to be settled from my estate before any distribution: ',
    essayHeldWith: ', held with {institution}',
    essayValuedAt: ', valued at approximately {amount}',
    essayOwedTo: ', owed to {institution}',
    essayInAmount: ', in the amount of {amount}',
    essayNetEstate:
      'After settlement of these obligations, my net estate today amounts to approximately {amount}.',
    listJoin: '; ',
    listJoinLast: '; and ',
    netJoin: ' and ',
    // Signature completion certificate
    certTitle: 'Signature Certificate',
    certIntro:
      'All signatures on this will are digital. No ink or paper signature is accepted or required. Each signing event below is time-stamped and recorded with the signer’s IP address.',
    certDocId: 'Document ID',
    certIntegrity: 'Document integrity (SHA-256)',
    certSealed: 'Sealed',
    certDisclaimer: 'Disclaimer accepted',
    certVersion: 'version',
    certSigner: 'Signer',
    certRole: 'Role',
    certRoleTestator: 'Testator',
    certRoleWitness: 'Witness',
    certRoleTrustee: 'Trustee',
    certStatus: 'Status',
    certSignedDigitally: 'Signed digitally',
    certConfirmedDigitally: 'Confirmed digitally',
    certPending: 'Pending',
    certIdMatched: 'Name verified',
    certIdPending: 'Name not verified',
    certTimestamp: 'Timestamp (UTC)',
    certIp: 'IP address',
    certDevice: 'Device',
    certNone: '—',
    certFooter:
      'This certificate is bound to the document above. Any change to the will invalidates the integrity hash.',
  },
  ar: {
    title: 'الوصية الأخيرة',
    ofName: 'لـ {name}',
    draft: 'مسودة — لم تُختم بعد',
    willNo: 'وصية رقم {id}',
    sealedOn: 'خُتمت {date}',
    witnessesConfirmed: 'تأكّد {n} من الشهود',
    witnessConfirmedOne: 'تأكّد شاهد واحد',
    wordsTitle: 'كلمات لعائلتي',
    wishesTitle: 'رغبات الجنازة والدفن',
    wish1: 'الغسل والتكفين وفق السنة',
    wish2: 'دفن بسيط — بلا إسراف ولا تأخير',
    wish3: 'ادفنوني في أقرب مقبرة للمسلمين',
    wish4: 'أقيموا عزاءً — ثلاثة أيام لا أكثر',
    wish4no: 'لا عزاء — يكفي الدعاء',
    estateTitle: 'الأصول والالتزامات',
    netEstate: 'صافي التركة',
    estateNote: 'جرد التركة كما سُجِّل عند الختم؛ وتُسدَّد الديون قبل توزيع الأنصبة.',
    divisionTitle: 'قسمة التركة',
    noHeirs: 'لا يوجد ورثة مسجّلون.',
    bequestRow: 'الوصية',
    bequestBasis: 'من الثلث — خارج الفرائض',
    witnessesTitle: 'الشهود والوصي',
    witnessesCol: 'الشهود',
    trusteeCol: 'الوصي',
    witnessRole: 'شاهد',
    trusteeRole: 'الوصي',
    testatorRole: 'الموصي',
    signedDigitally: 'وُقّع رقميًا',
    pending: 'قيد الانتظار',
    pendingCode: 'الرمز معلّق',
    noneRecorded: 'لا يوجد.',
    sealLine: 'خُتمت وشُهدت عبر وصيتي',
    docDisclaimer:
      'أنصبة الفرائض هنا محسوبة للإرشاد وليست فتوى أو استشارة قانونية؛ وتُقسم التركة وفق الشريعة (الفرائض) على المذهب الذي اختاره الموصي.',
    disclaimer:
      'تُحتسب الأنصبة وفق الفرائض. لا تقدّم «وصيتي» استشارة قانونية؛ وتختلف المتطلبات باختلاف الولاية القضائية، وقد تحتاج هذه الوثيقة إلى شهود أو توثيق لتكون نافذة.',
    // Heading and mode vocabulary match the app's own AR copy (cwGuardTitle,
    // cwGParentLbl, cwGNamedLbl) so the document reads back what the owner chose.
    guardianHeading: 'الولاية على الأولاد القُصّر',
    guardianRowLabel: 'الوليّ',
    guardianColPhone: 'الهاتف',
    guardianColEmail: 'البريد الإلكتروني',
    guardianParentValue: 'الوالد الآخر',
    guardianIslamicValue: 'تُحدَّد وفق ترتيب الولاية الشرعي',
    guardianParentNote: 'يكون الوالد الآخر وليًّا على كل ولد قاصر وعلى نصيبه حتى يبلغ.',
    guardianIslamicNote:
      'تُحدَّد الولاية وفق ترتيب الولاية الشرعي المعمول به في المذهب المثبت في هذه الوصية، عند نفاذها. ولا تنص هذه الوثيقة على ذلك الترتيب.',
    // "الشخص المذكور أعلاه" rather than "المذكور أعلاه": the app never collects the
    // guardian's gender, and hanging the agreement on الشخص ("the person") keeps the
    // clause correct for a woman without guessing. Same reason essayGuardianContact
    // below carries no pronoun — «معه» would address a female guardian as "him".
    guardianNamedNote: 'يُعيَّن الشخص المذكور أعلاه وليًّا على كل ولد قاصر وعلى نصيبه حتى يبلغ.',
    essayGuardianParent:
      'وأوصي بأن تكون رعاية أولادي القُصّر ورعاية نصيب كل واحد منهم إلى والدهم الآخر حتى يبلغوا.',
    essayGuardianIslamic:
      'وأوصي بأن تُحدَّد الولاية على أولادي القُصّر وعلى نصيب كل واحد منهم وفق ترتيب الولاية الشرعي المعمول به في المذهب المثبت في هذه الوصية، عند نفاذ هذه الوصية. ولا أُثبت ذلك الترتيب هنا؛ وإنما يُرجع فيه إلى أهل العلم أو إلى القضاء.',
    essayGuardianNamed:
      'وأعيّن {name} وليًّا على أولادي القُصّر وعلى نصيب كل واحد منهم حتى يبلغوا.',
    essayGuardianContact: ' ويمكن التواصل على {contact}.',
    essayAssetsLead: 'أُقرّ بأنني، حتى ختم هذه الوصية، أملك الأصول التالية: ',
    essayLiabilitiesLead:
      'وأُقرّ كذلك بالديون والالتزامات التالية، وتُسدَّد من تركتي قبل أي قسمة: ',
    essayHeldWith: '، لدى {institution}',
    essayValuedAt: '، بقيمة تقديرية {amount}',
    essayOwedTo: '، مستحقة لجهة {institution}',
    essayInAmount: '، بمبلغ {amount}',
    essayNetEstate: 'وبعد سداد هذه الالتزامات، يبلغ صافي تركتي اليوم ما يقارب {amount}.',
    listJoin: '؛ ',
    listJoinLast: '؛ و',
    netJoin: ' و',
    certTitle: 'شهادة التوقيع',
    certIntro:
      'جميع التواقيع على هذه الوصية رقمية. لا يُقبل توقيع بالحبر أو الورق ولا يُشترط. وكل توقيع أدناه مؤرَّخ ومسجَّل مع عنوان IP للموقِّع.',
    certDocId: 'رقم الوثيقة',
    certIntegrity: 'سلامة الوثيقة (SHA-256)',
    certSealed: 'خُتمت',
    certDisclaimer: 'قُبل إخلاء المسؤولية',
    certVersion: 'إصدار',
    certSigner: 'الموقِّع',
    certRole: 'الصفة',
    certRoleTestator: 'الموصي',
    certRoleWitness: 'الشاهد',
    certRoleTrustee: 'الوصي',
    certStatus: 'الحالة',
    certSignedDigitally: 'وُقِّع رقميًا',
    certConfirmedDigitally: 'أُكِّد رقميًا',
    certPending: 'قيد الانتظار',
    certIdMatched: 'تطابق الاسم',
    certIdPending: 'لم يُتحقَّق الاسم',
    certTimestamp: 'الوقت (UTC)',
    certIp: 'عنوان IP',
    certDevice: 'الجهاز',
    certNone: '—',
    certFooter: 'هذه الشهادة مرتبطة بالوثيقة أعلاه. وأي تغيير في الوصية يُبطل بصمة السلامة.',
  },
};

/**
 * A content hash for tamper evidence, like Adobe Sign's document integrity field.
 * Computed over the CANONICAL will content (heirs, shares, bequests, message) so any
 * change to what was signed changes the hash. Excludes signing metadata, which is
 * recorded separately on the certificate.
 */
function contentHash(w: WillDocumentData): string {
  const canonical = JSON.stringify({
    id: w.id,
    shares: w.shariaShares.map((s) => [s.heirRelation, s.heirName, String(s.sharePercent)]),
    bequests: w.bequests.map((b) => [b.beneficiaryName, String(b.sharePercent)]),
    message: w.personalMessage ?? '',
  });
  return createHash('sha256').update(canonical).digest('hex');
}

function fmtTs(d: Date | null | undefined, rtl: boolean): string {
  if (!d) return '—';
  const iso = new Date(d).toISOString().replace('T', ' ').slice(0, 19);
  return rtl ? toArabicDigits(iso) : iso;
}

/** A short, non-identifying device summary from the user-agent (never the raw UA). */
function deviceOf(ua: string | null | undefined): string {
  if (!ua) return '—';
  const os = /Windows/i.test(ua)
    ? 'Windows'
    : /iPhone|iPad|iOS/i.test(ua)
      ? 'iOS'
      : /Android/i.test(ua)
        ? 'Android'
        : /Mac OS X|Macintosh/i.test(ua)
          ? 'macOS'
          : /Linux/i.test(ua)
            ? 'Linux'
            : '—';
  const browser = /Edg\//i.test(ua)
    ? 'Edge'
    : /Chrome\//i.test(ua)
      ? 'Chrome'
      : /Safari\//i.test(ua)
        ? 'Safari'
        : /Firefox\//i.test(ua)
          ? 'Firefox'
          : '';
  return [os, browser].filter(Boolean).join(' · ') || '—';
}

/** Adobe Sign-style completion certificate: one audited row per signer. */
function certificatePage(w: WillDocumentData, lang: WillDocumentLang): string {
  const t = STRINGS[lang];
  const rtl = lang === 'ar';
  const testatorName = w.ownerEmail.split('@')[0];

  type Row = { name: string; role: string; status: string; idChip?: string; at?: Date | null; ip?: string | null; ua?: string | null };
  const rows: Row[] = [];

  // Testator (the seal is their digital signature).
  rows.push({
    name: testatorName,
    role: t.certRoleTestator,
    status: w.signedAt ? t.certSignedDigitally : t.certPending,
    at: w.signedAt ?? w.sealedAt,
    ip: w.signedIp,
  });

  for (const x of w.witnesses) {
    rows.push({
      name: x.fullName,
      role: t.certRoleWitness,
      status: x.status === 'SIGNED' ? t.certSignedDigitally : t.certPending,
      idChip: x.idMatchStatus === 'MATCHED' ? t.certIdMatched : t.certIdPending,
      at: x.signedAt,
      ip: x.ipAddress,
      ua: x.userAgent,
    });
  }

  for (const x of w.trustees) {
    rows.push({
      name: x.fullName,
      role: t.certRoleTrustee,
      status: x.status === 'CONFIRMED' ? t.certConfirmedDigitally : t.certPending,
      at: x.confirmedAt,
      ip: x.ipAddress,
      ua: x.userAgent,
    });
  }

  const signerRows = rows
    .map(
      (r) => `<tr>
        <td>${esc(r.name)}${r.idChip ? `<br><span class="chip">${esc(r.idChip)}</span>` : ''}</td>
        <td class="muted">${esc(r.role)}</td>
        <td>${esc(r.status)}</td>
        <td class="mono">${fmtTs(r.at, rtl)}</td>
        <td class="mono">${esc(r.ip || t.certNone)}</td>
        <td class="muted">${esc(deviceOf(r.ua))}</td>
      </tr>`,
    )
    .join('');

  const disclaimerLine =
    w.disclaimerAcceptedAt && w.disclaimerVersion
      ? `<div><strong>${esc(t.certDisclaimer)}:</strong> ${esc(t.certVersion)} ${esc(w.disclaimerVersion)} · <span class="mono">${fmtTs(w.disclaimerAcceptedAt, rtl)}</span></div>`
      : '';

  return `
  <section class="certificate">
    <h2>${esc(t.certTitle)}</h2>
    <p class="cert-intro">${esc(t.certIntro)}</p>
    <div class="cert-meta">
      <div><strong>${esc(t.certDocId)}:</strong> <span class="mono">${esc(w.id)}</span></div>
      <div><strong>${esc(t.certIntegrity)}:</strong> <span class="mono hash">${esc(contentHash(w))}</span></div>
      ${w.sealedAt ? `<div><strong>${esc(t.certSealed)}:</strong> <span class="mono">${fmtTs(w.sealedAt, rtl)}</span></div>` : ''}
      ${disclaimerLine}
    </div>
    <table class="cert-table">
      <thead><tr>
        <th>${esc(t.certSigner)}</th><th>${esc(t.certRole)}</th><th>${esc(t.certStatus)}</th>
        <th>${esc(t.certTimestamp)}</th><th>${esc(t.certIp)}</th><th>${esc(t.certDevice)}</th>
      </tr></thead>
      <tbody>${signerRows}</tbody>
    </table>
    <p class="cert-footer">${esc(t.certFooter)}</p>
  </section>`;
}

/** Fills {name}/{relation}/{share}/{names} placeholders in a localized template. */
function fill(template: string, vars: Record<string, string>): string {
  return template.replace(/\{(\w+)\}/g, (_, k) => vars[k] ?? '');
}

/** "a; b; and c" (narrative estate list). Localized separators — Arabic uses ؛ / و. */
function joinItems(parts: string[], lang: WillDocumentLang): string {
  const t = STRINGS[lang];
  if (parts.length <= 1) return parts.join('');
  return parts.slice(0, -1).join(t.listJoin) + t.listJoinLast + parts[parts.length - 1];
}

// ---------------------------------------------------------------------------
// DV2.1 document sheet — the section builders, in the prototype's order:
// header · words · wishes · estate · division · (guardianship) · signatures ·
// sealed footer, then the signature certificate on its own page.
// ---------------------------------------------------------------------------

/**
 * The prototype's gold lock-seal (header) and check-rosette (sealed footer):
 * two rounded squares — one rotated 45° — in brass gold, with a cream padlock
 * or check. Verbatim vector paths from the DV2.1 canvas.
 */
const LOCK_SEAL_SVG = `<svg width="52" height="52" viewBox="0 0 100 100"><g transform="translate(50,50)"><rect x="-26" y="-26" width="52" height="52" rx="7" fill="#A87B33"></rect><rect x="-26" y="-26" width="52" height="52" rx="7" fill="#A87B33" transform="rotate(45)"></rect><path d="M-7 -4 v-5 a7 7 0 0 1 14 0 v5" fill="none" stroke="#F5EFE1" stroke-width="5"></path><rect x="-11" y="-4" width="22" height="17" rx="4" fill="#F5EFE1"></rect></g></svg>`;
const ROSETTE_SVG = `<svg width="120" height="120" viewBox="0 0 100 100"><g transform="translate(50,50)"><rect x="-26" y="-26" width="52" height="52" rx="7" fill="#A87B33"></rect><rect x="-26" y="-26" width="52" height="52" rx="7" fill="#A87B33" transform="rotate(45)"></rect><path d="M-11 1 L-3 9 L12 -9" fill="none" stroke="#F5EFE1" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"></path></g></svg>`;

const numFor = (lang: WillDocumentLang) => (n: number) =>
  lang === 'ar' ? toArabicDigits(String(n)) : String(n);

/** "Will #W-4821 · sealed 3 May 2026 · 2 witnesses confirmed" — header AND sealed footer. */
function docMetaLine(w: WillDocumentData, lang: WillDocumentLang): string {
  const t = STRINGS[lang];
  const num = numFor(lang);
  const willNo = fill(t.willNo, { id: esc(w.id.slice(0, 8).toUpperCase()) });
  if (w.status !== 'SEALED') return `${willNo} · ${esc(t.draft)}`;
  const confirmed = w.witnesses.filter((x) => x.status === 'SIGNED').length;
  return [
    willNo,
    fill(t.sealedOn, { date: fmtDate(w.sealedAt, lang) }),
    confirmed === 1 ? t.witnessConfirmedOne : fill(t.witnessesConfirmed, { n: num(confirmed) }),
  ].join(' · ');
}

/** Centered header: lock seal, bismillah (Amiri), title, testator line, meta. */
function headerSection(w: WillDocumentData, lang: WillDocumentLang): string {
  const t = STRINGS[lang];
  const rtl = lang === 'ar';
  const testatorName = w.ownerEmail.split('@')[0];
  const place = [w.testatorCity?.trim(), countryName(w.testatorCountry, lang)]
    .filter(Boolean)
    .join(rtl ? '، ' : ', ');
  const testatorLine =
    fill(t.ofName, { name: esc(testatorName) }) + (place ? ` — ${esc(place)}` : '');
  return `
  <header>
    ${LOCK_SEAL_SVG}
    <div class="bismillah" dir="rtl">بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ</div>
    <h1>${esc(t.title)}</h1>
    <div class="testator-line">${testatorLine}</div>
    <div class="doc-meta">${docMetaLine(w, lang)}</div>
  </header>`;
}

/** "Words for my family" — the only boxed section: sunken wash, quoted italic message. */
function wordsSection(w: WillDocumentData, lang: WillDocumentLang): string {
  const msg = w.personalMessage?.trim();
  if (!msg) return '';
  const t = STRINGS[lang];
  return `
  <section class="words">
    <div class="sec-label">${esc(t.wordsTitle)}</div>
    <div class="words-msg">“${esc(msg)}”</div>
  </section>`;
}

/**
 * Funeral & burial wishes, joined " · ". Only when the owner answered the wishes
 * step at all (funeralWishes non-null); the azaa flag always contributes a line —
 * true names the gathering, false records that duʿāʾ suffices.
 */
function wishesSection(w: WillDocumentData, lang: WillDocumentLang): string {
  const src = w.funeralWishes;
  if (!src || typeof src !== 'object') return '';
  const f = src as Record<string, unknown>;
  const t = STRINGS[lang];
  const items = [
    f.sunnah === true ? t.wish1 : null,
    f.simple === true ? t.wish2 : null,
    f.local === true ? t.wish3 : null,
    f.azaa === true ? t.wish4 : t.wish4no,
  ].filter(Boolean) as string[];
  return `
  <section>
    <div class="sec-label">${esc(t.wishesTitle)}</div>
    <div class="wishes">${items.map(esc).join(' · ')}</div>
  </section>`;
}

/** The estate inventory as narrative will language, for the "Narrative" estate format. */
function estateNarrative(
  w: WillDocumentData,
  lang: WillDocumentLang,
): { paras: string[]; net: string | null } {
  const items = w.assets ?? [];
  const t = STRINGS[lang];
  const money = moneyFor(lang);

  const item = (a: WillAsset, institutionTpl: string, amountTpl: string) => {
    let s = esc(a.label);
    if (a.institution) s += fill(institutionTpl, { institution: esc(a.institution) });
    if (a.estimatedValue != null) s += fill(amountTpl, { amount: money(a.currency, a.estimatedValue) });
    return s;
  };

  const assets = items.filter((a) => a.type !== 'LIABILITY');
  const liabilities = items.filter((a) => a.type === 'LIABILITY');
  const paras: string[] = [];

  if (assets.length) {
    paras.push(
      t.essayAssetsLead +
        joinItems(assets.map((a) => item(a, t.essayHeldWith, t.essayValuedAt)), lang) +
        '.',
    );
  }
  if (liabilities.length) {
    paras.push(
      t.essayLiabilitiesLead +
        joinItems(liabilities.map((a) => item(a, t.essayOwedTo, t.essayInAmount)), lang) +
        '.',
    );
  }

  const totals = assetTotals(items);
  const net = totals.length
    ? fill(t.essayNetEstate, { amount: totals.map((x) => money(x.currency, x.net)).join(t.netJoin) })
    : null;
  return { paras, net };
}

/**
 * "Assets & liabilities" — 2px gold top rule. Table format: bullet rows (green
 * assets / danger loans), Fraunces amounts, a net-estate row per currency, and
 * the inventory footnote. Narrative format: the same facts as justified will
 * prose. An item with no estimated value is still listed. No items → no section.
 */
function estateSection(
  w: WillDocumentData,
  lang: WillDocumentLang,
  format: WillDocumentFormat,
): string {
  const items = w.assets ?? [];
  if (!items.length) return '';
  const t = STRINGS[lang];
  const money = moneyFor(lang);

  let inner: string;
  if (format === 'essay') {
    const { paras, net } = estateNarrative(w, lang);
    inner =
      paras.map((p) => `<p class="estate-prose">${p}</p>`).join('') +
      (net ? `<p class="estate-prose net">${net}</p>` : '');
  } else {
    const row = (a: WillAsset, liability: boolean) => {
      const inst = a.institution ? ` <span class="inst">— ${esc(a.institution)}</span>` : '';
      const amount =
        a.estimatedValue == null ? '' : `${liability ? '− ' : ''}${money(a.currency, a.estimatedValue)}`;
      return `<div class="est-row">
        <span class="dot ${liability ? 'loan' : 'asset'}"></span>
        <span class="est-name">${esc(a.label)}${inst}</span>
        <span class="est-amt${liability ? ' loan' : ''}">${amount}</span>
      </div>`;
    };
    const assetRows = items.filter((a) => a.type !== 'LIABILITY').map((a) => row(a, false));
    const liabilityRows = items.filter((a) => a.type === 'LIABILITY').map((a) => row(a, true));
    const netRows = assetTotals(items).map(
      (x) => `<div class="est-row net">
        <span class="est-name net-label">${esc(t.netEstate)}</span>
        <span class="est-amt net-amt">${money(x.currency, x.net)}</span>
      </div>`,
    );
    inner = [...assetRows, ...liabilityRows, ...netRows].join('');
  }

  return `
  <section class="gold-rule">
    <div class="sec-label">${esc(t.estateTitle)}</div>
    ${inner}
    <div class="footnote">${esc(t.estateNote)}</div>
  </section>`;
}

/**
 * "Division of the estate" — 2px gold top rule. One row per heir: name + relation
 * (600), the scriptural basis (faint, the fiqh "why"), and the share in Fraunces.
 * Bequest rows close the section in gold ink. The basis prefers the strings the
 * API attached (findOne) and derives from the relation otherwise, so no share
 * ever prints without its basis.
 */
function divisionSection(
  w: WillDocumentData,
  lang: WillDocumentLang,
  display: WillDocumentDisplay,
): string {
  const t = STRINGS[lang];
  const share = shareFor(lang, display);
  const pct = pctFor(lang);

  const heirRows = w.shariaShares.length
    ? w.shariaShares
        .map((s) => {
          const basis =
            lang === 'ar'
              ? (s.basisAr ?? shareBasis(s.heirRelation).ar)
              : (s.basisEn ?? shareBasis(s.heirRelation).en);
          return `<div class="div-row">
            <span class="div-name">${esc(s.heirName)} — ${esc(relationLabel(s.heirRelation, lang))}</span>
            <span class="div-basis">${esc(basis)}</span>
            <span class="div-share">${share(s.sharePercent)}</span>
          </div>`;
        })
        .join('')
    : `<div class="div-row"><span class="div-basis">${esc(t.noHeirs)}</span></div>`;

  const bequestRows = w.bequests
    .map(
      (b) => `<div class="div-row bequest">
        <span class="div-name">${esc(t.bequestRow)} — ${esc(b.beneficiaryName)}</span>
        <span class="div-basis">${esc(t.bequestBasis)}</span>
        <span class="div-share">${pct(b.sharePercent)}</span>
      </div>`,
    )
    .join('');

  return `
  <section class="gold-rule">
    <div class="sec-label">${esc(t.divisionTitle)}</div>
    ${heirRows}
    ${bequestRows}
  </section>`;
}

type GuardianMode = 'parent' | 'islamic' | 'named';

/**
 * Resolves the guardianship clause, or null when the document must stay silent.
 *
 * The gate is the same one the review screen uses (`guardianMode` non-empty), so the
 * sealed PDF says exactly what the owner proofread before sealing — the question is
 * only asked of owners with minor children, and `guardianMode` stays NULL on a will
 * whose owner never answered it. An empty "Guardianship" heading in a will is worse
 * than no heading: it reads as a deliberate refusal to name anyone.
 *
 * Two ways to get null beyond "never answered":
 *   - an unrecognised mode. The column is a free String (the enum lives only in the
 *     DTO), so a value written around the API must not fall through to a default —
 *     silence is recoverable, misstating who raises a child is not.
 *   - mode 'named' with no name. There is no appointment to record, and "I appoint
 *     ___ as guardian" is a defect in an executed document. The owner sees the same
 *     gap on the review screen, which shows the placeholder label rather than a name.
 */
function guardianOf(
  w: WillDocumentData,
): { mode: GuardianMode; name: string; phone: string; email: string } | null {
  const mode = (w.guardianMode ?? '').trim().toLowerCase();
  if (mode !== 'parent' && mode !== 'islamic' && mode !== 'named') return null;
  const name = (w.guardianName ?? '').trim();
  if (mode === 'named' && !name) return null;
  return { mode, name, phone: (w.guardianPhone ?? '').trim(), email: (w.guardianEmail ?? '').trim() };
}

/**
 * Contact details stay LTR and keep Western digits even in the AR document: a phone
 * number is for dialling and an address for typing, so neither is reordered by the
 * surrounding RTL run nor converted to Arabic-Indic digits the way share figures are.
 */
const ltr = (s: string) => `<span dir="ltr">${esc(s)}</span>`;

/**
 * "Guardianship of minor children" — hairline top rule, omitted entirely when null.
 * Table format: labelled rows + the appointment note. Narrative format: the same
 * clause in first person, matching the estate narrative's register.
 */
function guardianSection(
  w: WillDocumentData,
  lang: WillDocumentLang,
  format: WillDocumentFormat,
): string {
  const g = guardianOf(w);
  if (!g) return '';
  const t = STRINGS[lang];

  let inner: string;
  if (format === 'essay') {
    let para: string;
    if (g.mode === 'parent') para = t.essayGuardianParent;
    else if (g.mode === 'islamic') para = t.essayGuardianIslamic;
    else {
      para = fill(t.essayGuardianNamed, { name: esc(g.name) });
      const contact = [g.phone, g.email].filter(Boolean).map(ltr);
      if (contact.length) para += fill(t.essayGuardianContact, { contact: contact.join(' · ') });
    }
    inner = `<p class="estate-prose">${para}</p>`;
  } else {
    const value =
      g.mode === 'named'
        ? esc(g.name)
        : g.mode === 'islamic'
          ? esc(t.guardianIslamicValue)
          : esc(t.guardianParentValue);
    const note =
      g.mode === 'named' ? t.guardianNamedNote : g.mode === 'islamic' ? t.guardianIslamicNote : t.guardianParentNote;
    const rows = [
      `<div class="guard-row"><span class="g-label">${esc(t.guardianRowLabel)}</span><span class="g-value">${value}</span></div>`,
    ];
    // Contact only ever exists for a named guardian — updateGuardian clears it otherwise.
    if (g.mode === 'named' && g.phone) {
      rows.push(
        `<div class="guard-row"><span class="g-label">${esc(t.guardianColPhone)}</span><span class="g-value">${ltr(g.phone)}</span></div>`,
      );
    }
    if (g.mode === 'named' && g.email) {
      rows.push(
        `<div class="guard-row"><span class="g-label">${esc(t.guardianColEmail)}</span><span class="g-value">${ltr(g.email)}</span></div>`,
      );
    }
    inner = `${rows.join('')}<div class="footnote">${esc(note)}</div>`;
  }

  return `
  <section class="hair-rule">
    <div class="sec-label">${esc(t.guardianHeading)}</div>
    ${inner}
  </section>`;
}

/**
 * "Witnesses & trustee" — hairline top rule. Two columns (witnesses | trustee),
 * each signature the prototype's stack: the name as Fraunces-italic "handwriting",
 * the printed name ON a hairline rule, then role · signed digitally · date. An
 * unsigned party shows an em-dash and its pending state (the trustee adds their
 * contact, so the family can chase the code). The testator's larger signature
 * closes the section full-width, over a 1.5px ink rule.
 */
function signaturesSection(w: WillDocumentData, lang: WillDocumentLang): string {
  const t = STRINGS[lang];
  const testatorName = w.ownerEmail.split('@')[0];

  const sig = (name: string, role: string, signed: boolean, at: Date | null | undefined, pendingLabel: string, contact = '') => {
    const script = signed
      ? `<span class="script">${esc(name)}</span>`
      : `<span class="script pending">—</span>`;
    const meta = signed
      ? `${esc(role)} · ${esc(t.signedDigitally)}${at ? ` · ${fmtDate(at, lang)}` : ''}`
      : `${esc(role)} · ${esc(pendingLabel)}`;
    return `<div class="sig">
      ${script}
      <span class="sig-name">${esc(name)}</span>
      <span class="sig-meta">${meta}</span>
      ${contact ? `<span class="sig-contact">${contact}</span>` : ''}
    </div>`;
  };

  const witnessCol = w.witnesses.length
    ? w.witnesses.map((x) => sig(x.fullName, t.witnessRole, x.status === 'SIGNED', x.signedAt, t.pending)).join('')
    : `<div class="sig-meta muted-line">${esc(t.noneRecorded)}</div>`;

  const trusteeCol = w.trustees.length
    ? w.trustees
        .map((x) => {
          const confirmed = x.status === 'CONFIRMED';
          const contact = confirmed
            ? ''
            : [x.phone, x.email].filter(Boolean).map((v) => ltr(String(v))).join(' · ');
          return sig(x.fullName, t.trusteeRole, confirmed, x.confirmedAt, t.pendingCode, contact);
        })
        .join('')
    : `<div class="sig-meta muted-line">${esc(t.noneRecorded)}</div>`;

  const testatorSigned = Boolean(w.signedAt) || w.status === 'SEALED';
  const testatorMetaParts = testatorSigned
    ? [
        esc(t.testatorRole),
        esc(t.signedDigitally),
        fmtDate(w.signedAt ?? w.sealedAt, lang),
        ...(w.testatorCity?.trim() ? [esc(w.testatorCity.trim())] : []),
      ]
    : [esc(t.testatorRole), esc(t.pending)];

  return `
  <section class="hair-rule">
    <div class="sec-label">${esc(t.witnessesTitle)}</div>
    <div class="sig-grid">
      <div class="sig-col">
        <div class="col-label">${esc(t.witnessesCol)}</div>
        ${witnessCol}
      </div>
      <div class="sig-col">
        <div class="col-label">${esc(t.trusteeCol)}</div>
        ${trusteeCol}
      </div>
    </div>
    <div class="sig testator">
      ${testatorSigned ? `<span class="script">${esc(testatorName)}</span>` : `<span class="script pending">—</span>`}
      <span class="sig-name">${esc(testatorName)}</span>
      <span class="sig-meta">${testatorMetaParts.join(' · ')}</span>
    </div>
  </section>`;
}

/**
 * The sealed footer: gold check-rosette, "Sealed & witnessed via Wasiati", the
 * document meta line again, then the two disclaimers (the DV2.1 guidance line and
 * the jurisdiction line). A draft carries only the disclaimers — no rosette until
 * the will is actually sealed.
 */
function sealFooterSection(w: WillDocumentData, lang: WillDocumentLang): string {
  const t = STRINGS[lang];
  const sealed = w.status === 'SEALED';
  const sealBlock = sealed
    ? `${ROSETTE_SVG}
      <div class="seal-line">${esc(t.sealLine)}</div>
      <div class="seal-meta">${docMetaLine(w, lang)}</div>`
    : '';
  return `
  <footer class="seal-footer">
    ${sealBlock}
    <div class="doc-disclaimer">${esc(t.docDisclaimer)}</div>
    <div class="doc-disclaimer">${esc(t.disclaimer)}</div>
  </footer>`;
}

/** Exported for tests: builds the document HTML without launching Chromium. */
export function buildWillHtml(
  w: WillDocumentData,
  format: WillDocumentFormat,
  lang: WillDocumentLang,
  display: WillDocumentDisplay = 'percent',
): string {
  return buildHtml(w, format, lang, display);
}

function buildHtml(
  w: WillDocumentData,
  format: WillDocumentFormat,
  lang: WillDocumentLang,
  display: WillDocumentDisplay = 'percent',
): string {
  const rtl = lang === 'ar';

  // AR replaces both Latin faces with IBM Plex Sans Arabic (DV2.1 --fontD/--fontU
  // swap); EN embeds the Arabic UI face too, so Arabic heir names inside an English
  // document still resolve rather than falling to a host font.
  const fonts = rtl
    ? [
        fontFace('IBM Plex Sans Arabic', 'IBMPlexSansArabic-Regular.ttf', '400'),
        fontFace('IBM Plex Sans Arabic', 'IBMPlexSansArabic-SemiBold.ttf', '600'),
        fontFace('IBM Plex Sans Arabic', 'IBMPlexSansArabic-Bold.ttf', '700'),
        fontFace('Amiri', 'Amiri-Regular.ttf', '400'),
      ]
    : [
        fontFace('Fraunces', 'Fraunces.ttf', '100 900'),
        fontFace('Public Sans', 'PublicSans.ttf', '100 900'),
        fontFace('IBM Plex Sans Arabic', 'IBMPlexSansArabic-Regular.ttf', '400'),
        fontFace('Amiri', 'Amiri-Regular.ttf', '400'),
      ];

  const fontD = rtl ? "'IBM Plex Sans Arabic', sans-serif" : "'Fraunces', serif";
  const fontU = rtl
    ? "'IBM Plex Sans Arabic', 'Amiri', sans-serif"
    : "'Public Sans', 'IBM Plex Sans Arabic', sans-serif";
  // Letter-spacing is Latin typography; tracking out Arabic breaks its joins.
  const track = (v: string) => (rtl ? '0' : v);

  return `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
  ${fonts.join('\n')}
  @page { size: A4; }
  * { box-sizing: border-box; }
  /* DV2.1 sheet tokens. Text inks are the app's "Ironclad" tier (DECISIONS §22):
     the prototype's --muted/--faint greys and --goldDeep were rejected by the owner
     as unreadable, so the document reads with the same inks the app ships. Fills
     and rules (gold, green, danger, hairlines) keep the prototype's values. */
  body {
    margin: 0;
    background: #ECE3D0; /* propagates to the page canvas — the page WASH, not the sheet */
    color: #1C2333;
    font-family: ${fontU};
    font-size: 13px;
    line-height: ${rtl ? 1.8 : 1.55};
    direction: ${rtl ? 'rtl' : 'ltr'};
  }
  /* The document is a parchment CARD floating on the wash — the prototype's sheet
     (card bg, 1px hair2 border, 6px radius, 44/46px padding), not a full-bleed
     page. First pass painted the whole page parchment and let the content run to
     the print margins; the owner compared it to the prototype and called it
     "attached to the edges". box-decoration-break: clone re-draws the border and
     padding on every printed page, so a will that runs long stays a stack of
     sheets rather than one card sliced open across the page break. */
  .sheet {
    background: #F5EFE1;
    border: 1px solid rgba(47,74,61,.25);
    border-radius: 6px;
    padding: 44px 46px;
    -webkit-box-decoration-break: clone;
    box-decoration-break: clone;
  }
  header {
    text-align: center;
    border-bottom: 2px solid #A87B33;
    padding-bottom: 18px;
  }
  header svg { display: block; margin: 0 auto 10px; }
  .bismillah { font-family: 'Amiri', serif; font-size: 18px; color: #714F14; }
  h1 { font-family: ${fontD}; font-size: 23px; font-weight: 600; margin: 8px 0 4px; }
  .testator-line { font-size: 12px; color: #454036; }
  .doc-meta { font-size: 11px; color: #524B40; margin-top: 4px; }

  section { margin-top: 18px; }
  .gold-rule { border-top: 2px solid #A87B33; padding-top: 14px; }
  .hair-rule { border-top: 1px solid rgba(47,74,61,.14); padding-top: 14px; }
  .sec-label {
    font-size: 11px; font-weight: 700; letter-spacing: ${track('.07em')};
    color: #714F14; text-transform: uppercase; margin-bottom: 6px;
    break-after: avoid;
  }

  .words { background: #ECE3D0; border: 1px solid rgba(47,74,61,.14); border-radius: 10px; padding: 16px 18px; }
  .words .sec-label { margin-bottom: 4px; }
  .words-msg { font-size: 13px; line-height: 1.7; font-style: italic; }

  .wishes { font-size: 12px; line-height: 1.7; color: #3E3A2F; }

  .est-row {
    display: flex; align-items: center; gap: 10px; padding: 6px 0;
    border-bottom: 1px dotted rgba(47,74,61,.25); font-size: 12.5px;
    break-inside: avoid;
  }
  .dot { width: 7px; height: 7px; border-radius: 2px; flex: none; }
  .dot.asset { background: #2F4A3D; }
  .dot.loan { background: #9E3B2E; }
  .est-name { flex: 1; font-weight: 600; }
  .est-name .inst { color: #454036; font-weight: 400; }
  .est-amt { font-family: ${fontD}; font-weight: 600; }
  .est-amt.loan { color: #9E3B2E; }
  .est-row.net { border-bottom: none; padding: 8px 0 2px; }
  .net-label { color: #714F14; font-weight: 700; }
  .net-amt { font-family: ${fontD}; font-weight: 700; color: #2F4A3D; }
  .footnote { font-size: 10.5px; color: #524B40; line-height: 1.5; margin-top: 4px; }
  .estate-prose { font-size: 12.5px; line-height: 1.9; color: #3E3A2F; text-align: justify; margin: 0 0 10px; }
  .estate-prose.net { font-weight: 600; color: #1C2333; }

  .div-row {
    display: flex; align-items: baseline; gap: 10px; padding: 8px 0;
    border-bottom: 1px dotted rgba(47,74,61,.25); font-size: 13px;
    break-inside: avoid;
  }
  .div-row:last-of-type, .div-row.bequest { border-bottom: none; }
  .div-name { font-weight: 600; }
  .div-basis { flex: 1; font-size: 11px; color: #524B40; line-height: 1.4; }
  .div-share { font-family: ${fontD}; font-weight: 600; white-space: nowrap; }
  .div-row.bequest .div-name, .div-row.bequest .div-share { color: #714F14; }

  .guard-row { display: flex; gap: 10px; padding: 4px 0; font-size: 12.5px; }
  .g-label { color: #454036; min-width: 90px; }
  .g-value { font-weight: 600; }

  .sig-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; margin-top: 6px; }
  .col-label {
    font-size: 10px; font-weight: 700; letter-spacing: ${track('.06em')};
    color: #524B40; text-transform: uppercase; margin-bottom: 10px;
  }
  .sig { display: flex; flex-direction: column; gap: 2px; margin-bottom: 14px; break-inside: avoid; }
  .script { font-family: ${fontD}; font-style: italic; font-size: 19px; color: #1C2333; padding: 2px 0; }
  .script.pending { color: #524B40; font-style: normal; }
  .sig-name { border-top: 1px solid rgba(47,74,61,.25); padding-top: 5px; font-size: 11.5px; font-weight: 600; }
  .sig-meta { font-size: 10px; color: #524B40; }
  .sig-contact { font-size: 10px; color: #714F14; }
  .muted-line { padding: 2px 0; }
  .sig.testator { margin: 8px 0 0; }
  .sig.testator .script { font-size: 26px; padding: 4px 0; }
  .sig.testator .sig-name { border-top: 1.5px solid #1C2333; padding-top: 6px; font-weight: 700; max-width: 260px; }
  .sig.testator .sig-meta { font-size: 10.5px; }

  .seal-footer { text-align: center; margin-top: 22px; padding-top: 10px; }
  .seal-footer svg { display: block; margin: 0 auto 10px; }
  .seal-line { font-size: 12px; font-weight: 700; }
  .seal-meta { font-size: 10.5px; color: #524B40; margin-top: 4px; }
  .doc-disclaimer { font-size: 10px; color: #524B40; line-height: 1.5; max-width: 440px; margin: 8px auto 0; }

  /* Signature completion certificate — its own page (the break sits on the sheet
     wrapper so the new page opens with the card's own top border, not a slice). */
  .cert-sheet { page-break-before: always; margin-top: 14px; }
  .certificate h2 { font-family: ${fontD}; font-size: 19px; font-weight: 600; margin: 0 0 3mm; }
  .cert-intro { font-size: 10pt; color: #454036; }
  .cert-meta { font-size: 9pt; margin: 4mm 0; line-height: 1.7; }
  .cert-meta .mono { color: #223529; }
  .mono { font-family: "Consolas", "SF Mono", monospace; font-variant-numeric: tabular-nums; }
  .hash { word-break: break-all; font-size: 8pt; }
  table { width: 100%; border-collapse: collapse; }
  td, th { padding: 2mm 0; border-bottom: 1px solid rgba(47,74,61,.14); text-align: start; }
  .muted { color: #454036; }
  .cert-table { font-size: 8.5pt; }
  .cert-table th { font-size: 7.5pt; text-transform: uppercase; letter-spacing: ${track('0.5px')}; color: #524B40; }
  .chip {
    display: inline-block; font-size: 7pt; padding: 0.3mm 1.5mm; border-radius: 2mm;
    background: #DCE5DE; color: #2F4A3D; margin-top: 0.5mm;
  }
  .cert-footer { font-size: 8pt; color: #524B40; margin-top: 4mm; font-style: italic; }
</style>
</head>
<body>
  <div class="sheet">
    ${headerSection(w, lang)}
    ${wordsSection(w, lang)}
    ${wishesSection(w, lang)}
    ${estateSection(w, lang, format)}
    ${divisionSection(w, lang, display)}
    ${guardianSection(w, lang, format)}
    ${signaturesSection(w, lang)}
    ${sealFooterSection(w, lang)}
  </div>
  <div class="sheet cert-sheet">
    ${certificatePage(w, lang)}
  </div>
</body>
</html>`;
}
