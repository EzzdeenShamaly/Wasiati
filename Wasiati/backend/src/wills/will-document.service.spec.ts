// Puppeteer is ESM and pulls in a browser binary; the HTML builder needs neither.
// Stub it so importing the service does not drag Chromium into the test.
jest.mock('puppeteer', () => ({ __esModule: true, default: { launch: jest.fn() } }));

import { buildWillHtml, WillDocumentData } from './will-document.service';

/**
 * The document is the DV2.1 "Will export" sheet (prototype lines 1685-1812):
 * lock-seal header with the bismillah, the boxed family message, funeral wishes,
 * the estate with its gold top rule, the division rows with each share's fiqh
 * basis, the two-column signature grid, and the sealed rosette footer — in EN and
 * AR (full RTL, Arabic-Indic numerals).
 *
 * The ESTATE FORMAT toggle changes how the assets & loans READ — a listed table
 * or narrative will language — and nothing else: the rest of the sheet keeps its
 * structure in both formats (DV2.1: only the ASSETS & LIABILITIES block swaps).
 *
 * These test the HTML the PDF is rendered FROM, so no browser is needed. The one
 * thing they can't prove here is Chromium's Arabic SHAPING; that is asserted
 * separately by extracting presentation forms from a real PDF (integration).
 */
const will = (over: Partial<WillDocumentData> = {}): WillDocumentData => ({
  id: 'w-123',
  ownerEmail: 'ahmed@example.com',
  tier: 'STANDARD',
  status: 'SEALED',
  sealedAt: new Date('2026-07-01T00:00:00Z'),
  personalMessage: null,
  shariaShares: [
    { heirName: 'Zainab', heirRelation: 'WIFE', sharePercent: 12.5 },
    { heirName: 'Yusuf', heirRelation: 'SON', sharePercent: 58.33 },
    { heirName: 'Maryam', heirRelation: 'DAUGHTER', sharePercent: 29.17 },
  ],
  bequests: [{ beneficiaryName: 'Local mosque', sharePercent: 10 }],
  witnesses: [{ fullName: 'Khalid', status: 'SIGNED' }],
  trustees: [{ fullName: 'Fatima' }],
  ...over,
});

describe('will document HTML', () => {
  describe('the DV2.1 sheet (English, table estate)', () => {
    const html = buildWillHtml(will(), 'table', 'en');
    it('is LTR and renders the division rows with shares', () => {
      expect(html).toContain('direction: ltr');
      expect(html).toContain('Division of the estate');
      expect(html).toContain('Zainab');
      expect(html).toContain('58.33%');
      expect(html).toContain('Last Will &amp; Testament');
    });
    it('opens with the lock seal and the bismillah, and closes sealed with the rosette', () => {
      expect(html).toContain('بِسْمِ اللَّهِ');
      expect(html).toContain('M-7 -4 v-5 a7 7 0 0 1 14 0 v5'); // padlock path (header seal)
      expect(html).toContain('M-11 1 L-3 9 L12 -9'); // check path (sealed rosette)
      expect(html).toContain('Sealed &amp; witnessed via Wasiati');
    });
    it('carries the meta line: will number, seal date, witnesses confirmed', () => {
      expect(html).toContain('Will #W-123');
      expect(html).toContain('sealed 1 July 2026');
      expect(html).toContain('1 witness confirmed');
    });
    it('prints each share with its scriptural basis, derived from the relation when not supplied', () => {
      expect(html).toContain('Qur’an 4:12'); // wife
      expect(html).toContain('Qur’an 4:11'); // daughter
    });
    it('prefers the basis strings the API attached over re-deriving them', () => {
      const w = will({
        shariaShares: [{ heirName: 'Zainab', heirRelation: 'WIFE', sharePercent: 12.5, basisEn: 'CUSTOM-BASIS', basisAr: 'أساس' }],
      });
      expect(buildWillHtml(w, 'table', 'en')).toContain('CUSTOM-BASIS');
      expect(buildWillHtml(w, 'table', 'ar')).toContain('أساس');
    });
    it('closes the division with the bequest in gold ink', () => {
      expect(html).toContain('Bequest — Local mosque');
      expect(html).toContain('From the free third');
    });
    it('renders the signature grid: script signature for the signed, em-dash for the pending', () => {
      // Khalid signed — his name appears twice in the stack (script + printed rule).
      expect(html).toContain('Witnesses &amp; trustee');
      expect(html.match(/Khalid/g)!.length).toBeGreaterThanOrEqual(2);
      // Fatima (trustee, no status) is pending: dash plus the pending-code note.
      expect(html).toContain('pending code');
      // The testator signs the sheet full-width.
      expect(html).toContain('class="sig testator"');
      expect(html).toContain('ahmed'); // testator name from the owner email
    });
  });

  describe('shares as fractions (the SHARES AS toggle)', () => {
    it('renders every share over the classical denominators — the prototype fracOf', () => {
      // The toggle must visibly change EVERY row, not just the Qur'anic sixths and
      // eighths — an earlier canonical-only pass left residue shares as percentages
      // and read as a dead toggle.
      const html = buildWillHtml(will(), 'table', 'en', 'fraction');
      expect(html).toContain('1/8'); // 12.5 — the wife's eighth
      expect(html).toContain('7/12'); // 58.33 — the son's residue share
      expect(html).toContain('7/24'); // 29.17 — the daughter's residue share
      expect(html).not.toContain('58.33%');
    });
    it('falls back to % for a share with no clean fraction', () => {
      const w = will({ shariaShares: [{ heirName: 'X', heirRelation: 'SON', sharePercent: 45.5 }] });
      expect(buildWillHtml(w, 'table', 'en', 'fraction')).toContain('45.50%');
    });
    it('keeps the bequest as a percentage — the free third is user-chosen', () => {
      const html = buildWillHtml(will(), 'table', 'en', 'fraction');
      expect(html).toContain('10%');
    });
  });

  describe('narrative estate (English)', () => {
    const html = buildWillHtml(will(), 'essay', 'en');
    it('keeps the division as rows — only the estate block reads differently', () => {
      expect(html).toContain('Division of the estate');
      expect(html).toContain('Zainab — Wife');
      expect(html).toContain('58.33%');
    });
    it('keeps the signature grid and the sealed footer', () => {
      expect(html).toContain('Witnesses &amp; trustee');
      expect(html).toContain('Fatima');
      expect(html).toContain('Khalid');
      expect(html).toContain('Sealed &amp; witnessed via Wasiati');
    });
  });

  describe('the testator line', () => {
    it('names the city and country after the name when the profile has them', () => {
      const html = buildWillHtml(will({ testatorCity: 'Toronto', testatorCountry: 'CA' }), 'table', 'en');
      expect(html).toContain('of ahmed');
      expect(html).toContain('Toronto, Canada');
    });
    it('omits the place entirely when the profile has no address', () => {
      const html = buildWillHtml(will(), 'table', 'en');
      expect(html).toContain('of ahmed');
      expect(html).not.toContain('of ahmed — ');
    });
  });

  describe('funeral & burial wishes', () => {
    it('joins the chosen wishes with a middot and records the azaa choice either way', () => {
      const html = buildWillHtml(
        will({ funeralWishes: { sunnah: true, simple: true, local: false, azaa: false } }),
        'table',
        'en',
      );
      expect(html).toContain('Funeral &amp; burial wishes');
      expect(html).toContain('Ghusl and shrouding per the Sunnah · A simple burial — no extravagance, no delay · No ʿazāʾ gathering — duʿāʾ suffices');
      expect(html).not.toContain('nearest Muslim cemetery'); // local: false
    });
    it('renders no wishes section at all when the owner never answered', () => {
      const html = buildWillHtml(will(), 'table', 'en');
      expect(html).not.toContain('Funeral &amp; burial wishes');
    });
    it('localises the wishes in the AR document', () => {
      const html = buildWillHtml(
        will({ funeralWishes: { sunnah: true, simple: false, local: false, azaa: true } }),
        'table',
        'ar',
      );
      expect(html).toContain('الغسل والتكفين وفق السنة');
      expect(html).toContain('أقيموا عزاءً');
    });
  });

  describe('Arabic (table estate)', () => {
    const html = buildWillHtml(will(), 'table', 'ar');
    it('is RTL and uses the Arabic chrome', () => {
      expect(html).toContain('direction: rtl');
      expect(html).toContain('الوصية الأخيرة'); // title
      expect(html).toContain('قسمة التركة'); // division heading
      expect(html).toContain('الشهود والوصي'); // witnesses & trustee
    });
    it('localises relations and uses Arabic-Indic numerals for shares', () => {
      expect(html).toContain('الزوجة'); // wife
      expect(html).toContain('الابن'); // son
      expect(html).toContain('٥٨٫٣٣٪'); // 58.33% in Arabic-Indic
      expect(html).not.toContain('58.33%');
    });
  });

  describe('Arabic (narrative estate)', () => {
    const html = buildWillHtml(will(), 'essay', 'ar');
    it('is RTL with Arabic-Indic shares', () => {
      expect(html).toContain('direction: rtl');
      expect(html).toContain('١٢٫٥٠٪'); // 12.50%
    });
  });

  describe('bayt al-māl heir', () => {
    it('is labelled, in both languages, not shown as a raw enum', () => {
      const w = will({ shariaShares: [{ heirName: '—', heirRelation: 'BAYT_AL_MAL', sharePercent: 50 }] });
      expect(buildWillHtml(w, 'table', 'en')).toContain('Public treasury');
      expect(buildWillHtml(w, 'table', 'ar')).toContain('بيت المال');
    });
  });

  describe('safety', () => {
    it('escapes a malicious heir name in every format', () => {
      const w = will({ shariaShares: [{ heirName: '<script>x</script>', heirRelation: 'SON', sharePercent: 100 }] });
      for (const fmt of ['table', 'essay'] as const) {
        for (const lang of ['en', 'ar'] as const) {
          const html = buildWillHtml(w, fmt, lang);
          expect(html).not.toContain('<script>x</script>');
          expect(html).toContain('&lt;script&gt;');
        }
      }
    });

    it('renders a draft header — and NO rosette — when not sealed', () => {
      const html = buildWillHtml(will({ status: 'DRAFT', sealedAt: null }), 'table', 'en');
      expect(html).toContain('Draft — not yet sealed');
      expect(html).not.toContain('Sealed &amp; witnessed via Wasiati');
      expect(html).not.toContain('M-11 1 L-3 9 L12 -9'); // rosette check path
    });

    it('handles a will with no heirs gracefully in both formats', () => {
      const w = will({ shariaShares: [], bequests: [] });
      expect(buildWillHtml(w, 'table', 'en')).toContain('No heirs recorded');
      expect(buildWillHtml(w, 'essay', 'en')).toContain('No heirs recorded');
    });
  });

  describe('assets & liabilities', () => {
    // 850,000 + 184,000 − 34,000 = SAR 1,000,000 net.
    const withAssets = (over: Partial<WillDocumentData> = {}) =>
      will({
        personalMessage: 'Be kind to one another.',
        assets: [
          { type: 'REAL_ESTATE', label: 'Apartment in Jeddah', institution: null, estimatedValue: 850000, currency: 'SAR' },
          { type: 'BANK_ACCOUNT', label: 'Savings account', institution: 'Al Rajhi Bank', estimatedValue: 184000, currency: 'SAR' },
          { type: 'OTHER', label: 'Family library', institution: null, estimatedValue: null, currency: null },
          { type: 'LIABILITY', label: 'Car loan', institution: 'Al Rajhi Bank', estimatedValue: 34000, currency: 'SAR' },
        ],
        ...over,
      });

    it('table: lists assets and liabilities with separated thousands and a net-estate row', () => {
      const html = buildWillHtml(withAssets(), 'table', 'en');
      expect(html).toContain('Assets &amp; liabilities');
      expect(html).toContain('Apartment in Jeddah');
      expect(html).toContain('SAR 184,000');
      expect(html).toContain('− SAR 34,000'); // liability rendered negative
      expect(html).toContain('Family library'); // no value — still listed
      expect(html).toContain('Net estate');
      expect(html).toContain('SAR 1,000,000');
    });

    it('table: colours the rows — green asset bullets, danger loans', () => {
      const html = buildWillHtml(withAssets(), 'table', 'en');
      expect(html).toContain('class="dot asset"');
      expect(html).toContain('class="dot loan"');
      expect(html).toContain('est-amt loan');
    });

    it('sits after the family message and before the division of the estate', () => {
      const html = buildWillHtml(withAssets(), 'table', 'en');
      const message = html.indexOf('Words for my family');
      const assets = html.indexOf('Assets &amp; liabilities');
      const division = html.indexOf('Division of the estate');
      expect(message).toBeGreaterThan(-1);
      expect(assets).toBeGreaterThan(message);
      expect(division).toBeGreaterThan(assets);
    });

    it('narrative: declares assets, debts and the net estate in the prescribed wording', () => {
      const html = buildWillHtml(withAssets(), 'essay', 'en');
      expect(html).toContain(
        'I declare that, as of the sealing of this will, I own the following assets: ' +
          'Apartment in Jeddah, valued at approximately SAR 850,000; ' +
          'Savings account, held with Al Rajhi Bank, valued at approximately SAR 184,000; ' +
          'and Family library.',
      );
      expect(html).toContain(
        'I further declare the following debts and obligations, to be settled from my estate ' +
          'before any distribution: Car loan, owed to Al Rajhi Bank, in the amount of SAR 34,000.',
      );
      expect(html).toContain(
        'After settlement of these obligations, my net estate today amounts to approximately SAR 1,000,000.',
      );
      expect(html).toContain(
        'Estate inventory as recorded at sealing; debts are settled before the shares are distributed.',
      );
      // Declared before the shares are divided.
      expect(html.indexOf('I own the following assets')).toBeLessThan(
        html.indexOf('Division of the estate'),
      );
    });

    it('renders Arabic with Arabic-Indic digits and separators in both formats', () => {
      const table = buildWillHtml(withAssets(), 'table', 'ar');
      expect(table).toContain('الأصول والالتزامات'); // heading
      expect(table).toContain('صافي التركة'); // net estate
      expect(table).toContain('SAR ١٨٤٬٠٠٠');
      expect(table).toContain('SAR ١٬٠٠٠٬٠٠٠');
      expect(table).not.toContain('184,000');

      const essay = buildWillHtml(withAssets(), 'essay', 'ar');
      expect(essay).toContain('أملك الأصول التالية'); // assets declaration
      expect(essay).toContain('SAR ١٬٠٠٠٬٠٠٠'); // net
    });

    it('escapes a malicious label and institution in every format and language', () => {
      const w = will({
        assets: [
          {
            type: 'BANK_ACCOUNT',
            label: '<script>x</script>',
            institution: '<img src=x onerror=alert(1)>',
            estimatedValue: 5,
            currency: 'USD',
          },
        ],
      });
      for (const fmt of ['table', 'essay'] as const) {
        for (const lang of ['en', 'ar'] as const) {
          const html = buildWillHtml(w, fmt, lang);
          expect(html).not.toContain('<script>x</script>');
          expect(html).not.toContain('<img src=x');
          expect(html).toContain('&lt;script&gt;');
          expect(html).toContain('&lt;img src=x');
        }
      }
    });

    it('renders no section at all when the will has no assets', () => {
      for (const w of [will(), will({ assets: [] })]) {
        const table = buildWillHtml(w, 'table', 'en');
        expect(table).not.toContain('Assets &amp; liabilities');
        expect(table).not.toContain('Net estate');
        const essay = buildWillHtml(w, 'essay', 'en');
        expect(essay).not.toContain('I own the following assets');
        expect(essay).not.toContain('Estate inventory as recorded at sealing');
      }
    });
  });

  describe('signature completion certificate (Adobe Sign-style)', () => {
    const signed = () =>
      will({
        signedAt: new Date('2026-07-01T10:00:00Z'),
        signedIp: '203.0.113.7',
        disclaimerVersion: 'v3',
        disclaimerAcceptedAt: new Date('2026-06-30T09:00:00Z'),
        witnesses: [
          {
            fullName: 'Khalid',
            status: 'SIGNED',
            signedAt: new Date('2026-07-01T11:30:00Z'),
            ipAddress: '198.51.100.22',
            userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) Safari/605',
            idMatchStatus: 'MATCHED',
          },
        ],
        trustees: [
          {
            fullName: 'Fatima',
            status: 'CONFIRMED',
            confirmedAt: new Date('2026-07-02T08:00:00Z'),
            ipAddress: '192.0.2.44',
            userAgent: 'Mozilla/5.0 (Windows NT 10.0) Chrome/120',
          },
        ],
      });

    it('appends a certificate page listing every signer with IP and timestamp', () => {
      const html = buildWillHtml(signed(), 'table', 'en');
      expect(html).toContain('Signature Certificate');
      expect(html).toContain('page-break-before: always');
      // Testator, witness and trustee each appear with their IP.
      expect(html).toContain('203.0.113.7'); // testator
      expect(html).toContain('198.51.100.22'); // witness
      expect(html).toContain('192.0.2.44'); // trustee
    });

    it('reads "Signed digitally" and shows the ID-match chip — no ink path', () => {
      const html = buildWillHtml(signed(), 'table', 'en');
      expect(html).toContain('Signed digitally');
      expect(html).toContain('Name verified');
      expect(html).toContain('No ink or paper signature is accepted');
    });

    it('summarises the device from the user-agent, not the raw string', () => {
      const html = buildWillHtml(signed(), 'table', 'en');
      expect(html).toContain('iOS · Safari');
      expect(html).toContain('Windows · Chrome');
      expect(html).not.toContain('Mozilla/5.0'); // raw UA never leaked
    });

    it('includes a tamper-evidence hash that CHANGES when the will content changes', () => {
      const hashOf = (html: string) => {
        const m = html.match(/SHA-256[^>]*>[^<]*<span class="mono hash">([0-9a-f]{64})/);
        return m?.[1];
      };
      const base = hashOf(buildWillHtml(signed(), 'table', 'en'));
      expect(base).toMatch(/^[0-9a-f]{64}$/);

      // Change a share -> different hash.
      const tampered = signed();
      tampered.shariaShares[0] = { ...tampered.shariaShares[0], sharePercent: 99 };
      expect(hashOf(buildWillHtml(tampered, 'table', 'en'))).not.toBe(base);
    });

    it('the hash is stable for identical content, regardless of signing metadata', () => {
      const hashOf = (html: string) => html.match(/mono hash">([0-9a-f]{64})/)?.[1];
      const a = hashOf(buildWillHtml(signed(), 'table', 'en'));
      const b = hashOf(buildWillHtml(signed(), 'essay', 'ar')); // different format + lang
      expect(a).toBe(b); // same content -> same integrity hash
    });

    it('shows Pending / ID not verified for an unsigned witness', () => {
      const w = will({ witnesses: [{ fullName: 'Omar', status: 'PENDING', idMatchStatus: 'PENDING' }] });
      const html = buildWillHtml(w, 'table', 'en');
      expect(html).toContain('Pending');
      expect(html).toContain('Name not verified');
    });

    it('renders the certificate in Arabic with Arabic-Indic timestamps', () => {
      const html = buildWillHtml(signed(), 'table', 'ar');
      expect(html).toContain('شهادة التوقيع');
      expect(html).toContain('وُقِّع رقميًا');
      expect(html).toContain('تطابق الاسم');
    });

    it('a confirmed trustee signs the sheet in script; a pending one shows their contact', () => {
      const confirmed = buildWillHtml(signed(), 'table', 'en');
      expect(confirmed).not.toContain('pending code');

      const pending = buildWillHtml(
        will({ trustees: [{ fullName: 'Fatima', phone: '+966 50 882 4417', email: 'fatima@example.com' }] }),
        'table',
        'en',
      );
      expect(pending).toContain('pending code');
      expect(pending).toContain('<span dir="ltr">+966 50 882 4417</span>');
      expect(pending).toContain('fatima@example.com');
    });
  });

  /**
   * Guardianship of minor children.
   *
   * The owner picked a guardian in create-flow step 3, saw it echoed back on the review
   * screen, and sealed — and the sealed document said nothing about who raises their
   * children. The choice was persisted on the Will row and simply never rendered, so the
   * one artifact the family and any authority actually reads was silent on it.
   *
   * The gate is `guardianMode` non-empty — the same gate the review screen uses, so the
   * document cannot disagree with what the owner proofread. A will whose owner was never
   * asked (no minor children) has a NULL mode and must gain no heading at all: an empty
   * "Guardianship" section in an executed will reads as a refusal to name anyone.
   */
  describe('guardianship of minor children', () => {
    const named = (over: Partial<WillDocumentData> = {}) =>
      will({
        guardianMode: 'named',
        guardianName: 'Sara Haddad',
        guardianPhone: '+1 416 555 0142',
        guardianEmail: 'sara@example.com',
        ...over,
      });

    it('names the guardian in the English table and explains the appointment', () => {
      const html = buildWillHtml(named(), 'table', 'en');
      expect(html).toContain('Guardianship of minor children');
      expect(html).toContain('Sara Haddad');
      expect(html).toContain('+1 416 555 0142');
      expect(html).toContain('sara@example.com');
      expect(html).toContain('is appointed guardian of each child who is under age');
    });

    it('appoints the guardian in sentence form in the narrative format', () => {
      const html = buildWillHtml(named(), 'essay', 'en');
      expect(html).toContain('I appoint Sara Haddad as guardian of my children who are under age');
      expect(html).toContain('They may be reached at');
    });

    it('names the guardian in both Arabic formats', () => {
      // The table carries labelled rows; the narrative carries the clause as a
      // first-person sentence instead. Both must name the guardian.
      const table = buildWillHtml(named(), 'table', 'ar');
      expect(table).toContain('الولاية على الأولاد القُصّر'); // heading
      expect(table).toContain('يُعيَّن الشخص المذكور أعلاه وليًّا'); // appointment note

      const essay = buildWillHtml(named(), 'essay', 'ar');
      expect(essay).toContain('وليًّا على أولادي القُصّر'); // appointment sentence

      for (const html of [table, essay]) expect(html).toContain('Sara Haddad'); // name verbatim
    });

    it('keeps the guardian’s phone and email LTR and in Western digits inside the RTL document', () => {
      const html = buildWillHtml(named(), 'table', 'ar');
      // A phone number is for dialling: it must not be reordered by the surrounding RTL
      // run, nor converted to Arabic-Indic the way share figures are.
      expect(html).toContain('<span dir="ltr">+1 416 555 0142</span>');
      expect(html).not.toContain('٤١٦');
    });

    it('records the surviving parent without inventing a name', () => {
      const html = buildWillHtml(named({ guardianMode: 'parent', guardianName: null }), 'table', 'en');
      expect(html).toContain('The surviving parent');
      expect(html).toContain('until they come of age');
    });

    /**
     * The 'islamic' mode records the testator's DIRECTION and deliberately does not
     * state the order of guardianship itself. Nothing in docs/FIQH_REVIEW.md or
     * docs/DECISIONS.md resolves that order, and it diverges by school — so asserting
     * it in a sealed legal document would be an invented ruling. Pinned here so it is
     * not "helpfully" filled in later without a scholar's sign-off.
     */
    it('states the islamic mode as a direction, never asserting the order itself', () => {
      for (const format of ['table', 'essay'] as const) {
        const html = buildWillHtml(named({ guardianMode: 'islamic', guardianName: null }), format, 'en');
        expect(html).toContain('Islamic order of guardianship');
        // Table: "This document does not itself set out that order."
        // Narrative: "I do not set out that order here…"
        expect(html).toMatch(/(does not itself set out|do not set out) that order/);
        expect(html).not.toMatch(/paternal grandfather/i);
        expect(html).not.toMatch(/male relatives/i);
      }
    });

    it('adds NO section to a will without minor children', () => {
      // guardianMode is NULL — the question is only asked of owners with minors. Assert
      // on the WORD, not just the heading, in both formats.
      for (const format of ['table', 'essay'] as const) {
        expect(buildWillHtml(will(), format, 'en')).not.toMatch(/guardian/i);
        const ar = buildWillHtml(will(), format, 'ar');
        // NB: bare الولاية is no marker — the standing disclaimer says الولاية القضائية
        // ("jurisdiction"). القُصّر ("the minors") appears in the heading and in every
        // guardianship sentence, and nowhere else in the document.
        expect(ar).not.toContain('الولاية على الأولاد'); // heading
        expect(ar).not.toContain('القُصّر'); // minors
      }
    });

    it('stays silent rather than appointing a blank guardian or trusting an unknown mode', () => {
      // 'named' with no name would print "I appoint  as guardian" — a defect in an
      // executed document. An unrecognised mode must not fall through to a default:
      // silence is recoverable, misstating who raises a child is not.
      const blank = buildWillHtml(named({ guardianName: '  ' }), 'table', 'en');
      expect(blank).not.toMatch(/guardian/i);

      const unknown = buildWillHtml(named({ guardianMode: 'court' }), 'essay', 'en');
      expect(unknown).not.toMatch(/guardian/i);
      expect(unknown).not.toContain('Sara Haddad');
    });

    it('escapes a guardian name — the field is user-supplied', () => {
      const html = buildWillHtml(named({ guardianName: '<script>x</script>' }), 'table', 'en');
      expect(html).not.toContain('<script>x</script>');
      expect(html).toContain('&lt;script&gt;');
    });
  });
});
