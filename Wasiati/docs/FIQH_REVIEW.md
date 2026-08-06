# Fara'id engine — summary for scholarly review

**Prepared for a qualified Sharia board. Nothing here is a fatwa.**

This document states exactly what `backend/src/wills/sharia-calculator.ts` computes, the
position it follows, the schools that hold it, the recorded dissent, and a worked
numeric example for each rule. Please correct anything below; the engine is written so
each rule is a one-place change.

Sources were gathered by multi-source search with independent adversarial verification
(each claim needed 2 of 3 verifiers to survive). Claims marked **[3-0]** were confirmed
unanimously. Where classical and contemporary practice diverge, both are stated.

Status: **awaiting review.** Version of engine reviewed: the one in this commit.

---

## Summary of what the app offers

The engine accepts five school values, but for the heir set we model there are only
**three distinct divisions**:

| Mode offered | Radd | Grandfather with siblings | Identical to |
|---|---|---|---|
| **Jumhūr — majority (Ḥanbalī)** *(default)* | returns to sharers | muqāsama | Ḥanbalī |
| **Ḥanafī** | returns to sharers | **blocks them** | — |
| **Mālikī / Shāfiʿī — classical** | **bayt al-māl** | muqāsama | each other |

We deliberately do **not** list Ḥanbalī and Shāfiʿī as separate options: they would
produce identical numbers to an option already shown, implying a precision we do not
have. **Is this consolidation acceptable, or should all five be listed?**

---

## 1. Radd — return of surplus

**What we compute.** When the fixed shares (furūḍ) under-subscribe and there is no
ʿaṣaba, the surplus returns to the fixed-sharers in proportion to their shares. **The
spouse is excluded.** Under Mālikī/Shāfiʿī the surplus instead appears as a distinct
`bayt al-māl` line.

**Basis.**
- Radd is the doctrine of the Ḥanafī and Ḥanbalī schools; the Mālikī and Shāfiʿī
  schools follow Zayd b. Thābit that the residue goes to *bayt al-māl*. **[3-0]**
  *(IIUM, "Bayt al-Mal and Inheritance", citing Ibn ʿĀbidīn p.539; Ibn Qudāmah pp.47–48)*
- The surplus returns in proportion to the shares, **excluding husband and wife**,
  because radd is for blood-relative sharers. **[3-0]** *(Mughniyya, "Inheritance
  According to the Five Schools of Islamic Law", ch. al-Radd; al-islam.org)*

**Contemporary divergence — please advise.**
- Mālikī/Shāfiʿī condition *bayt al-māl*'s entitlement on a **properly administered**
  treasury (*bayt al-māl muntaẓim*). **[3-0]**
- Post-classical Mālikī and Shāfiʿī jurists **accept radd** where the treasury is
  mismanaged. **[3-0]** *(Dāwūd p.480; al-Sharbīnī p.7)*
- *"The majority of today's scholars, even Shāfiʿī scholars, are of the opinion that the
  residual net estate should go to the surviving farḍ legal heirs."* **[3-0]**
  *(ISRA/Emerald, IJIF, doi 10.1108/ijif-04-2019-0055)*
- Singapore's Syariah Court still directs residual estates to the MUIS-managed
  *bayt al-māl* on the early Shāfiʿī view. **[3-0]** *(same source)*
- Indonesia's Compilation of Islamic Law (KHI) **includes the spouse** in radd,
  diverging from the classical majority. **[3-0]**

> **RESOLVED (owner, 11 July 2026).** All schools apply **contemporary radd** — the
> surplus returns to the heirs, not bayt al-māl. For the heirs we model this makes
> Mālikī/Shāfiʿī/Ḥanbalī identical to Jumhūr, so the picker is now **Jumhūr vs Ḥanafī**.
> `bayt al-māl` remains only for a genuinely unclaimable surplus (e.g. a lone spouse).
> **Board: please confirm this is the correct default for your jurisdictions.**

**Worked example — wife + mother, no other heirs.**

| | Jumhūr / Ḥanafī / Ḥanbalī | Mālikī / Shāfiʿī (classical) |
|---|---|---|
| Wife | ¼ = **25%** | ¼ = **25%** |
| Mother | ⅓ + radd = **75%** | ⅓ = **33.33%** |
| Bayt al-māl | — | **41.67%** |

---

## 2. Grandfather with siblings (al-jadd waʾl-ikhwa)

**What we compute.** Ḥanafī: the true paternal grandfather blocks full and consanguine
siblings entirely. All other schools: *muqāsama* — the grandfather takes the **better of
muqāsama (sharing as a brother, male counted double) or ⅓ of the residue**, and never
less than ⅙ of the estate when fixed-sharers are present. The grandfather blocks
**uterine** siblings in every school.

**Basis.**
- The Ḥanafī school allows the grandfather to totally exclude the agnatic (full and
  consanguine) siblings; the majority view is that they are **not** excluded. **[3-0]**
- The grandfather **excludes uterine siblings** but inherits alongside full and
  consanguine siblings — Zayd b. Thābit's position, followed by Mālikī, Shāfiʿī and
  Ḥanbalī. **[3-0]**
- With siblings and no other heirs he takes whichever is more favourable: **⅓ or
  muqāsama**. **[3-0]**

**Known gap — muʿādda ("counting-in"). [3-0]**
> Consanguine siblings should be counted alongside full siblings when **sizing** the
> grandfather's share, then drop out in favour of the full siblings. Our engine counts
> consanguines only when no full sibling exists. In a mixed full+consanguine sibling case
> this can **overstate the grandfather's share**. This is not yet implemented and is
> flagged in the code. **Please confirm the correct treatment.**

**Worked examples.**

| Heirs | Ḥanafī | Jumhūr / Mālikī / Shāfiʿī / Ḥanbalī |
|---|---|---|
| Grandfather + 1 full brother | GF **100%**, brother 0 | GF **50%**, brother **50%** |
| Grandfather + son | GF ⅙ = **16.67%**, son **83.33%** | identical |
| Grandfather + daughter + full brother | daughter 50%, GF **50%**, brother 0 | daughter 50%, GF **25%**, brother **25%** |
| Grandfather + daughter + full sister | daughter 50%, GF **50%**, sister 0 | daughter 50%, GF **33.33%**, sister **16.67%** |
| Husband + daughter + grandfather + full brother | — | husband 25%, daughter 50%, GF **16.67%** (⅙-estate floor), brother **8.33%** |

**Correction (please verify). [needs review]**
> Until recently the engine gave the grandfather the **entire** residue — disinheriting
> the siblings (0%) — in *every* school whenever a daughter or son's daughter was present,
> i.e. it silently applied the Ḥanafī block outside Ḥanafī. This was corrected: with a
> female descendant the grandfather now shares with the siblings by muqāsama (the
> best-of-three above, ⅙-estate floor included), matching the Zayd doctrine. The
> daughter-present rows above are the new outputs. **Please confirm these figures and the
> compound (spouse + daughter + siblings) cases before production.** The muʿādda gap below
> still stands and compounds with these cases.

---

## 3. Al-Gharrāwayn / al-ʿUmariyyatān

**What we compute.** With a spouse and both parents and no children or siblings, the
mother takes **⅓ of the residue after the spouse**, not ⅓ of the estate.

Husband + mother + father → **50% / 16.67% / 33.33%**.

All four schools agree; Ibn ʿAbbās dissented. *(This was the single most important case
to get right: the design prototype we inherited computed 50 / 33.33 / 16.67, which we
believe to be an error. **Please confirm.**)*

*Verification note: the adversarial check on this claim did not complete — it is asserted
from the classical consensus and is flagged here as a priority for review.*

---

## 4. ʿAwl

**What we compute.** When the fixed shares over-subscribe, every share shrinks
proportionally; no heir is dropped. Applied identically in all five modes.

Husband + 2 full sisters = ½ + ⅔ = 7/6 → husband **42.86%**, each sister **28.57%**.

All four schools accept ʿawl; Ibn ʿAbbās rejected it.

*Verification note: this claim's adversarial check did not complete. Flagged for review.*

---

## 5. Unclaimed surplus

If a surplus can be claimed by nobody — for example only a husband survives — we assign
it to a visible **bayt al-māl** line so the division always totals exactly 100%, rather
than letting it silently vanish.

Lone husband → husband **50%**, bayt al-māl **50%**.

> **Question for the board.** Under Ḥanafī/Ḥanbalī (and post-classical Shāfiʿī) the
> *dhawū al-arḥām* should take **before** the treasury here. We do not yet model them
> (see below), so the treasury takes. Is showing the treasury the right interim
> behaviour, or should the app decline to compute this case?

---

## 6. Dhawū al-arḥām — NOT IMPLEMENTED

Distant kindred: daughter's children, sister's children, maternal uncles and aunts.

- Ḥanafī, Ḥanbalī and post-classical Shāfiʿīs (al-Muzanī, Ibn Surayj) **admit** them
  when there is no sharer besides a spouse and no ʿaṣaba. Mālikīs and early Shāfiʿīs
  **deny** them; the surplus goes to *bayt al-māl*. **[3-0]**

Implementing them requires new heir relations and an ordering method
(*ahl al-tanzīl* vs *ahl al-qarāba*). **We would like guidance on which ordering to use
before building it.**

---

## 7. Rules applied identically in all modes

Stated here so the board can confirm each. The engine models: spouse; sons and
daughters; agnatic grandchildren (son's son / son's daughter); father; mother; true
paternal grandfather; paternal and maternal grandmothers; full, consanguine and uterine
siblings; nephews; paternal uncles; cousins.

- Wife ⅛ with children, ¼ without; husband ¼ with children, ½ without (Q 4:12). Multiple
  wives split the single spousal share equally.
- Mother ⅙ with children or with two or more siblings, else ⅓ (Q 4:11). Siblings restrict
  her even when they are themselves blocked.
- Daughters alone: ½ (one) or ⅔ shared (two or more) (Q 4:11); with a son they become
  ʿaṣaba bi-ghayrihi at 2:1.
- Father: ⅙ with children, plus the residue when there is no son.
- Uterine siblings share **equally regardless of sex** (⅙ one, ⅓ two or more); blocked by
  any descendant or by the father/grandfather.
- Full sisters alongside daughters become residuaries (*ʿaṣaba maʿa al-ghayr*).
- Kalāla sisters: ½ or ⅔ (Q 4:176).
- ʿAṣaba priority: son → son's son → father → grandfather → full siblings → consanguine
  siblings → nephews → paternal uncles → cousins.
- Bequests are capped at ⅓ of the estate; debts settle before any division.

**Not modelled:** al-Akdariyya; the musharraka / Ḥimāriyya case; walāʾ (the freed-slave
patron, obsolete); *takmilat al-thuluthayn* edge cases beyond the granddaughter's ⅙.

---

---

## 8. Zakat estimator

**What we compute.** `zakatDue = 2.5% × (cash + bank + shares + gold)`, but only when
that total reaches the niṣāb of **85 g of gold**. Below the niṣāb, nothing is due.
The rate is *rubʿ al-ʿushr*. The result is rounded **down** so we never overstate an
obligation. The user is shown a prominent warning that this is guidance, not a ruling.

**Deliberate exclusions.**
- **Crypto never enters the base.** Its zakatability is contested and the product takes
  no position. It is *disclosed* as excluded, not silently dropped.
- Real estate, vehicles, pensions and business ownership are outside the base. They are
  either not zakatable in the common case or need rules (trade goods, growth assets)
  this estimator does not model.

**Open questions for the board.**

1. **Debts are NOT deducted.** The spec defines the base additively. Classical practice
   commonly deducts immediate debts from the zakatable total. Should liabilities the
   user has recorded be subtracted before applying the niṣāb test and the 2.5%?
2. **Niṣāb by gold, not silver.** We use 85 g of gold. The silver niṣāb (595 g) is lower
   and would make more users liable. Which should the estimator use — or should it offer
   the choice?
3. **Bank balances** are treated as cash. Correct for a current account; is it correct
   for a fixed deposit?
4. **Mixed currencies.** Where a holding is in a currency with no fixed peg to the
   user's own (e.g. CAD against SAR), we **exclude it and say so** rather than convert
   at a guessed rate. Is disclosure-and-exclude the right behaviour, or should the app
   decline to produce any figure at all until every holding can be valued?
5. **The gold price is configuration**, updated by an operator. If it is unset the
   estimate returns a 503 rather than using a stale niṣāb. Is that acceptable?

---

## 9. Guardianship of minor children — ḥaḍāna vs wilāya

**What we render.** The guardian step (create-flow step 3) offers three modes: `parent`
(the surviving parent), `islamic` (the sharia order), `named` (a specific person). All
three are now rendered into the sealed will document. For `islamic` the document records
the testator's **direction** — that guardianship be determined by the Islamic order
applicable under the school recorded in the will, at the time the will takes effect — and
**explicitly states that the document does not itself set out that order.** That
non-assertion is deliberate and is pinned by a test; it must not be "helpfully" completed
without the board's sign-off. Nothing in this file or `docs/DECISIONS.md` resolves the
order, and the research below is why.

> ✅ **RESOLVED 22 Jul 2026 — `docs/DECISIONS.md` §22.** The on-screen copy used to assert an
> order: `cwGIslamicNote` read *"Guardianship follows the sharia order — the father, then the
> paternal grandfather, then male relatives of the father's line — as determined at the time"*
> (AR: «تتبع الولاية الترتيب الشرعي — الأب ثم الجد لأب ثم عصبة الأب — بحسب الحال عند التنفيذ»),
> which conflates three distinct doctrines and states a **Ḥanafī-only** rule as if it were
> agreed. It has been replaced with a non-assertion that names no order, distinguishes care
> from guardianship of the share in plain language, and points the testator at `named`. **The
> new wording still wants a scholar's eye — see row 9b in the sign-off table** — but it no
> longer states a rule we cannot defend. The label `cwGIslamicLbl` and the card subtitle
> `cwGuardSub` were left alone and still use *order* framing; that is open (§22, scope note).

**Basis.**

- **Ḥaḍāna (physical custody) and wilāya (legal guardianship) are distinct offices**; a
  child can lawfully be in the mother's ḥaḍāna while the father holds wilāya. Wilāya
  subdivides into *wilāya ʿalā al-nafs* (person) and *wilāya ʿalā al-māl* (property).
  **[3-0]** *(Mughniyya, "The Five Schools of Islamic Law", ch. al-Ḥiḍāna; Musawah Policy
  Brief 6, "Upholding the Best Interests of the Child")*
- **Ḥaḍāna begins with the MOTHER in all four Sunni schools**, then runs through the
  maternal female line before reaching any male. Ḥanafī: mother → mother's mother →
  father's mother → sisters → aunts. Mālikī: mother → her mother h.h.s. → maternal aunts.
  Shāfiʿī: mother → her mothers h.h.s. → *then* father. Ḥanbalī: mother → her mother →
  father → his mothers → grandfather. **[3-0]** *(Mughniyya, ch. al-Ḥiḍāna; Hossain,
  "Ḥaḍānah (Custody) in Islamic Law")*
- **The app's sentence is therefore wrong about custody.** In no school does custody start
  with the father. The copy does not say "property", so a reader — and a court — will read
  it as covering who raises the child. **[3-0]** *(entailed by the two claims above)*
- **General ʿaṣaba (brothers, uncles) do NOT take automatic wilāya over a minor's property
  in any of the four schools.** Where father, grandfather and waṣī are absent, authority
  passes to the **qāḍī / court**, not to the nearest male agnate. **[3-0]** *(IslamQA
  126208; IslamWeb 68530; alhamdlilah.com: «ولا تثبت ولاية المال لغير هؤلاء كالأخ والعم
  والأم إلا بوصاية»; IslamOnline: «وسائر العصبات لا ولاية لهم إلا بالوصية»)*
- **The father's right to appoint a waṣī over his minor children by will is agreed across
  the four schools.** This is the juristic basis of our `named` mode, and it is the
  best-supported claim in this section — every school's ordering below contains "his
  waṣī", which presupposes the power. **[3-0]** *(IslamWeb 37701; alhamdlilah.com)*

**Per-school order of *wilāya ʿalā al-māl* (guardianship of the minor's property).**

| School | Order over the minor's property | Grandfather automatic? |
|---|---|---|
| **Ḥanafī** | father → father's waṣī → (waṣī's waṣī) → **paternal grandfather** → grandfather's waṣī → qāḍī | yes, but **after** the father's waṣī |
| **Shāfiʿī** | father → **paternal grandfather** → waṣī of whichever survived last → qāḍī | yes, **before** any waṣī |
| **Mālikī** | father → father's waṣī → (waṣī's waṣī) → qāḍī | **no** — only by the father's appointment |
| **Ḥanbalī** | father → father's waṣī → qāḍī | **no** — only by the father's appointment |

- Ḥanafī, Shāfiʿī and Mālikī orderings: **[3-0]** *(IslamWeb 37701, citing al-Zuhaylī,
  "al-Fiqh al-Islāmī wa-Adillatuh" 10/7328; IslamQA 126208; alhamdlilah.com)*
- **Ḥanbalī groups with Mālikī, not Shāfiʿī** — the grandfather takes nothing
  automatically. **[3-1]** *(confirming: IslamWeb 37701; IslamQA 126208; alhamdlilah.com;
  mawdoo3. Contradicting: English-language summaries deriving from Mughniyya giving
  Ḥanbalī "father → executor → order of inheritance → ḥākim" — but that passage is about
  **matrimonial** guardianship, not property.)*
- Shāfiʿī is stated classically by al-Nawawī in *al-Minhāj*: «ولي الصبي أبوه ثم جده ثم
  وصيهما ثم القاضي ولا تلي الأم في الأصح». **[3-1]** *(mawdoo3 instead gives Shāfiʿī as
  father → waṣī → grandfather; treated as an error against al-Zuhaylī and the Minhāj text,
  but the dissent is recorded.)*

**Where the app's sentence probably came from.** The "father → paternal grandfather →
ʿaṣaba" chain is a real fiqh order — it is the Ḥanafī **wilāya ʿalā al-nafs** order (and
the order for **marriage** guardianship), which does run through the agnates by inheritance
rank. **[3-0]** *(Almerja, "al-Awliyāʾ fī al-madhhab al-Ḥanafī"; IslamOnline, "al-Wilāya
ʿalā al-nafs")* The copy is not baseless — it imports a Ḥanafī person/marriage rule,
presents it as "the sharia order", and applies it on a screen users read as *who will raise
my children*.

**Open questions for the board.**

1. **Should `islamic` mode state any order at all?** The document currently does not, on
   the view that a sealed will reciting a contested, school-specific order invites
   challenge. Is a referral to "the applicable rules and the competent court" acceptable?
2. **If an order must be stated, which school**, and stated separately for ḥaḍāna, wilāya
   ʿalā al-nafs and wilāya ʿalā al-māl? These three have *different* answers and one
   sentence cannot carry all three.
3. **Our market is the US and Canada**, where a civil court appoints a minor's guardian and
   will not defer to a recited fiqh ordering. Should `islamic` mode be framed as a
   **precatory wish** guiding the court, with `named` as the operative choice?
4. **Should `named` be the recommended default?** It rests on the one point agreed across
   all four schools, and is the mode a North American probate court can give effect to.
5. **Does the mother's ḥaḍāna need its own disclosure**, so a testator does not believe
   that selecting `islamic` displaces her?

**Verification note — read before relying on this section.**
- The four per-school **property** orderings rest on four independent secondary sources
  that agree, but all four are contemporary fiqh portals; **al-Zuhaylī, Ibn ʿĀbidīn, Ibn
  Qudāmah, al-Dasūqī and al-Sharbīnī were not opened directly.** The locator "al-Zuhaylī
  10/7328" is reproduced *as cited by* IslamWeb and is **not independently verified**. No
  page number in this section should be treated as checked.
- The al-Nawawī *Minhāj* wording is quoted from a secondary source, not a fetched edition.
- Sabreen, "Guardianship of Property in Islamic Law", *Hamdard Islamicus* 44:1 (2021) is
  the most on-point peer-reviewed item located; its full text was blocked and could not be
  read. It is a lead, not a source.
- A **minority Ḥanbalī strand associated with Ibn Taymiyya** on who takes property
  guardianship in default is described *inconsistently* by our sources (one: "the nearest
  capable relative"; another: "the mother, for her greater compassion"). This did not reach
  unanimity and is **unresolved** — please do not rely on our summary of it.
- Several English-language "Muslim law" sources are **Anglo-Muḥammadan (Indian)**
  restatements of a Ḥanafī baseline, and at least three silently substituted the
  **matrimonial** guardianship order for the property order. That same conflation appears
  to be the origin of the app's current sentence, and is a live contamination risk for
  anyone re-running this research.

## Testing

Every rule above is pinned by automated tests
(`backend/src/wills/sharia-calculator.spec.ts`), and the Flutter live-preview engine is
tested against the same expectations so the preview cannot drift from the server. The
server is authoritative; the client preview is advisory.

## Reviewer sign-off

| Rule | Correct? | Corrections / notes |
|---|---|---|
| 1. Radd + spouse exclusion | | |
| 1b. Mālikī/Shāfiʿī: classical or contemporary? | | |
| 2. Grandfather muqāsama thresholds | | |
| 2b. Muʿādda treatment | | |
| 3. Al-Gharrāwayn | | |
| 4. ʿAwl | | |
| 5. Unclaimed surplus → bayt al-māl | | |
| 6. Dhawū al-arḥām ordering | | |
| 7. Common rules | | |
| 8a. Zakat base + crypto exclusion | | |
| 8b. Zakat: deduct debts? | | |
| 8c. Zakat: gold vs silver niṣāb | | |
| 9a. `islamic` mode states no order — correct? | | |
| 9b. In-app copy `cwGIslamicNote` — REWRITTEN to assert no order (DECISIONS §22); is the new wording sound? | | |
| 9e. `cwGIslamicLbl` / `cwGuardSub` still say "order" — acceptable? | | |
| 9c. Per-school wilāya ʿalā al-māl table | | |
| 9d. ḥaḍāna disclosure for the mother | | |

Reviewer: ______________________  Date: ____________
