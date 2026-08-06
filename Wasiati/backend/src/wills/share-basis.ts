/**
 * Scriptural basis for each heir's share, by RELATION.
 *
 * Transcribed from the design prototype's basis strings — the Qur'anic citations
 * (4:11 children/parents, 4:12 spouse/uterine, 4:176 kalāla), the Sunnah grandmother
 * rule, and the ʿaṣaba (residue) rules.
 *
 * Deliberately keyed on the relation, NOT the computed percentage: ʿawl scales every
 * share down and radd scales sharers up, and multiple heirs of one type divide a share,
 * so the final percent does NOT reliably imply a specific fard fraction (a mother reduced
 * to 13.3% by ʿawl is still a ⅙ sharer; two daughters at 50% each under radd are not an
 * "only daughter" at ½). Stating the RULE for the relation is therefore always correct,
 * where a percent-derived fraction would be wrong in ʿawl/radd cases. The share amounts
 * themselves remain the authority of `sharia-calculator.ts`.
 *
 * Fiqh content — pending scholar review (see docs/FIQH_REVIEW.md).
 */
export interface ShareBasis {
  en: string;
  ar: string;
}

export function shareBasis(relation: string): ShareBasis {
  switch (relation) {
    case 'HUSBAND':
      return { en: 'Qur’an 4:12 — one half (no children), one quarter (with children)', ar: 'النساء ١٢ — النِّصف بلا ولد، والرُّبع مع الولد' };
    case 'WIFE':
      return { en: 'Qur’an 4:12 — one quarter (no children) or one eighth (with children), shared among the wives', ar: 'النساء ١٢ — الرُّبع بلا ولد أو الثُّمن مع الولد، مقسومًا بين الزوجات' };
    case 'MOTHER':
      return { en: 'Qur’an 4:11 — one third, reduced to one sixth with children or two or more siblings', ar: 'النساء ١١ — الثلث، ويُخفَّض إلى السُّدس مع الولد أو مع اثنين فأكثر من الإخوة' };
    case 'FATHER':
      return { en: 'Qur’an 4:11 — one sixth with a son; one sixth plus the residue with only daughters; the whole residue (ʿaṣaba) with no children', ar: 'النساء ١١ — السُّدس مع الابن، والسُّدس مع الباقي تعصيبًا مع البنات، والباقي كله تعصيبًا بلا ولد' };
    case 'GRANDFATHER':
      return { en: 'In the father’s place (Qur’an 4:11 basis) — one sixth and/or the residue (ʿaṣaba)', ar: 'مقام الأب (النساء ١١) — السُّدس و/أو الباقي تعصيبًا' };
    case 'GRANDMOTHER':
    case 'PATERNAL_GRANDMOTHER':
    case 'MATERNAL_GRANDMOTHER':
      return { en: 'Sunnah — one sixth (when the mother is absent)', ar: 'السنة — السُّدس (عند فقد الأم)' };
    case 'SON':
      return { en: 'Residue (ʿaṣaba) — the son takes the remainder, 2:1 male to female (Qur’an 4:11)', ar: 'عصبة — للذكر مثل حظ الأنثيين (النساء ١١)' };
    case 'DAUGHTER':
      return { en: 'Qur’an 4:11 — one half (alone), two thirds (shared by two or more), or residue 2:1 alongside a son', ar: 'النساء ١١ — النِّصف للواحدة، والثلثان للاثنتين فأكثر، أو عصبة مع الابن' };
    case 'SON_SON':
      return { en: 'Residue (ʿaṣaba) — agnatic grandson, 2:1 male to female (Qur’an 4:11)', ar: 'عصبة — ابن الابن، للذكر مثل حظ الأنثيين (النساء ١١)' };
    case 'SON_DAUGHTER':
      return { en: 'Qur’an 4:11 — son’s daughter: as a daughter alone, or one sixth completing two thirds with a daughter', ar: 'النساء ١١ — بنت الابن: كالبنت منفردةً، أو السُّدس تكملةً للثلثين مع البنت' };
    case 'FULL_SISTER':
      return { en: 'Qur’an 4:176 (kalāla) — one half / two thirds, or residue alongside a daughter (maʿa al-ghayr)', ar: 'النساء ١٧٦ (الكلالة) — النِّصف أو الثلثان، أو عصبة مع البنت (مع الغير)' };
    case 'FULL_BROTHER':
      return { en: 'Residue (ʿaṣaba) — full brother, 2:1 male to female (Qur’an 4:176)', ar: 'عصبة — الأخ الشقيق، للذكر مثل حظ الأنثيين (النساء ١٧٦)' };
    case 'CONSANGUINE_SISTER':
      return { en: 'Qur’an 4:176 — consanguine (paternal) sister', ar: 'النساء ١٧٦ — الأخت لأب' };
    case 'CONSANGUINE_BROTHER':
      return { en: 'Residue (ʿaṣaba) — consanguine (paternal) brother', ar: 'عصبة — الأخ لأب' };
    case 'MATERNAL_SIBLING':
      return { en: 'Qur’an 4:12 — uterine sibling: one sixth alone, one third shared equally', ar: 'النساء ١٢ — الأخ لأم: السُّدس للواحد، والثلث للأكثر بالتساوي' };
    case 'FULL_NEPHEW':
    case 'CONSANGUINE_NEPHEW':
    case 'FULL_UNCLE':
    case 'CONSANGUINE_UNCLE':
    case 'FULL_COUSIN':
    case 'CONSANGUINE_COUSIN':
      return { en: 'Residue — the nearest male agnate (ʿaṣaba)', ar: 'عصبة — أقرب عاصب' };
    case 'BAYT_AL_MAL':
      return { en: 'Public treasury — no eligible heir for the surplus', ar: 'بيت المال — لا وارث للفائض' };
    default:
      return { en: 'Fixed share (farḍ) or residue (ʿaṣaba)', ar: 'فرض أو عصبة' };
  }
}
