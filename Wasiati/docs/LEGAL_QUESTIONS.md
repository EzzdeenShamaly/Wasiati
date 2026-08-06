# Questions for counsel — Wasiati (digital will platform)

**Purpose:** a briefing pack for US/Canada counsel (and, later, Saudi counsel). Everything
here is a question a lawyer must answer, not an engineering task. Each item states what the
product does **today**, the specific concern, the decision needed, and the source the
concern came from.

**Provenance:** compiled 29 Jul 2026 from a sourced review of GDPR/EDPB/ICO, CCPA
regulations, PIPEDA/OPC, Quebec Law 25, RUFADAA, and US legal-profession retention norms.
Sources are cited per item. **Nothing here is legal advice and none of it has been reviewed
by a lawyer** — several items are explicitly flagged as inference rather than verified
holdings.

---

## 0. What the product does (context)

A user writes a Sharia-compliant will, names heirs, records an asset inventory, uploads a
government ID and optionally records video messages. They nominate witnesses and trustees,
who confirm by one-time code. On death, a family member files a **death claim** (uploading
a death certificate); an admin reviews and **releases** it. Heirs and trustees then have a
**90-day access window**, after which all of the deceased's data is **permanently and
irreversibly destroyed**, leaving only an anonymised audit "tombstone".

Entity: UAE (Sharjah SHAMS free zone). Launch markets: **United States and Canada**;
Saudi Arabia later. Hosting: AWS `ca-central-1` (Canada), single region.

---

## 1. The 90-day destruction clock — is it defensible?

**Today:** everything is destroyed 90 days after release. Irreversibly and by design.

**Concern.** Two independent findings put pressure on this number:
- **Professional convention runs the other way.** Estate-planning files are conventionally
  retained permanently or for life-of-client-plus, and probate courts retain admitted wills
  permanently. The only mandatory US schedules found are for trust-account/client-property
  records (~7 years). So "purge at 90 days" is the *opposite* of the professional norm.
- **The timeline does not match probate reality.** Uncontested probate routinely exceeds
  90 days; contested estates run years. An heir can surface on day 120 needing the will
  that was destroyed on day 90.

**For comparison only** (does not bind us — we are not a covered entity): HIPAA protects a
decedent's records for **50 years**. It is the only US federal answer to "how long do a
dead person's records deserve protection," and the answer is not 90 days.

**Questions:**
1. Is a 90-day destruction of the testamentary instrument defensible, or does it create
   liability to an heir who arrives late?
2. Should the clock be **split by data class** — e.g. personal data at 90 days, but the
   will itself and the release evidence on a years-scale schedule keyed to probate closure?
3. Should the trigger be **estate closure or confirmed heir download**, rather than a fixed
   calendar countdown?
4. If we keep 90 days, is conspicuous disclosure at signup (not a ToS clause) sufficient to
   manage the expectation that we are *not* a permanent repository?

**Already built:** a **legal hold** (29 Jul 2026) that suspends the purge indefinitely for
a contested estate, checked before anything is destroyed. This addresses the litigation
case but not the "heir arrives late on an uncontested estate" case.

*Sources: [WSBA document retention guide](https://www.wsba.org/for-legal-professionals/member-support/practice-management-assistance/guides/document-retention-guide); [45 CFR 164.502](https://www.law.cornell.edu/cfr/text/45/164.502).*

---

## 2. RUFADAA — the documentary bar, and a product-design consequence

The Revised Uniform Fiduciary Access to Digital Assets Act (enacted in most US states)
governs a **custodian of digital assets** — which is what we are.

**Today:** a death claim is released on an uploaded death certificate plus admin review.

**Concern (a) — the evidence set.** RUFADAA's recognised bar for disclosing content is a
written request, a **certified** death certificate, **and** a certified copy of letters of
appointment, a small-estate affidavit, or a court order — plus the user's consent (or a
court direction) specifically for *content*. A death certificate alone is below that bar,
and the statutory good-faith protection attaches to the named documents.

**Concern (b) — the "online tool" priority rule. This one is concrete, not hypothetical.**
RUFADAA sets a three-tier priority: a custodian-provided **online tool** beats a will or
power of attorney, which beats the terms of service — **but the online tool only takes
priority if the user can modify or delete the direction at all times.**

Our heir-designation screen is such an online tool, and **it is frozen once the will is
sealed** — verified in the code: the heir-contacts service documents that the roster is
"editable only while the will is a DRAFT — a sealed will's roster is frozen", and edits to
a sealed will are refused. So for every sealed will — i.e. every *finished* will, the ones
that matter — the user can **not** modify the direction at all times.

If that forfeits online-tool priority, the designation stops overriding the will, which is
the entire legal value of the feature. Note the tension is real either way: freezing the
roster on seal is what makes the sealed instrument tamper-evident, so this is a genuine
trade-off between testamentary integrity and RUFADAA priority, not an oversight to patch.

**Questions:**
1. Should death-claim release require the full RUFADAA evidence set? What is the minimum
   that preserves good-faith immunity in our launch states?
2. Does freezing the heir roster on seal forfeit online-tool priority? If so, can we
   preserve both — e.g. a separate, always-editable digital-asset direction that sits
   outside the sealed instrument — or must one give way?
3. Do we need an explicit **consent-to-disclosure-of-content** checkbox, separate from
   designation, given content requires consent rather than mere nomination?
4. Which states' variations matter most for a US launch?

*Source: [RUFADAA as enacted, CA AB-691](https://leginfo.legislature.ca.gov/faces/billTextClient.xhtml?bill_id=201520160AB691).*

---

## 3. California's 30-day court-lodging duty

**Concern.** California imposes a duty on the custodian of a will to lodge it with the
superior court within 30 days of learning of the death. We learn of the death — that is
what a death claim *is*. If we destroy the will at day 90 without lodging it, a retention
choice becomes a statutory breach, with exposure that may be personal rather than corporate.

**Questions:**
1. Does this duty attach to us as an electronic custodian holding a digital will, or only
   to a custodian of a physical original?
2. If it attaches: what does lodging a *digital* will require in practice (print and file?
   chain-of-custody affidavit?), and is there a fee/venue issue at volume?
3. Which other states impose an equivalent duty, and does any Canadian province?
4. Should lodging become an automatic step on release in those jurisdictions?

---

## 4. Quebec — statutory limits on what heirs may receive

**Today:** on release, every heir/trustee gets access to the released material, and heirs
receive video messages.

**Concern.** Quebec's Law 25 (P-39.1) s. 41 requires an enterprise to **refuse** to
communicate a deceased's personal information to a liquidator, beneficiary, heir or
successor **unless the information affects their rights or interests in that capacity**.
Separately, s. 40.1 permits communication to a spouse or close relative where it could help
with **grieving** — and only if the deceased recorded no written refusal.

This maps onto our two content types differently: the will and share-relevant asset
inventory travel under s. 41 (they bear on entitlement), whereas a **personal video message
is better justified under the s. 40.1 grieving route** — which implies we must offer a
per-recipient toggle and durably store any written refusal, because honouring the refusal is
a *condition of the disclosure being lawful*.

**Questions:**
1. Does Law 25 apply to us for Quebec-resident users given we are a UAE entity hosting in
   Canada?
2. Does our current "release everything to everyone named" model comply with s. 41?
3. Do we need a per-recipient consent/refusal control for video messages, and what form
   must a "written refusal" take to be effective?

*Source: [P-39.1](https://www.canlii.org/en/qc/laws/stat/cqlr-c-p-39.1/latest/cqlr-c-p-39.1.html).*

---

## 5. The purge promise is contractual, not statutory — which raises the stakes on wording

**Finding:** the deceased are **outside** GDPR (Recital 27) and CCPA. So in the US and
Canada our purge is not a statutory duty — it is **our own published promise**, enforceable
as contract and, plausibly, as a deception claim.

**Concern.** Our riskiest sentence is any marketing claim that data is *"permanently and
irreversibly erased."* Once backups exist there will be a residual window (see
`BACKUP_RESTORE.md`), and the gap between the promise and the actual lifecycle is entirely
within our control to close before launch.

> **Flagged as inference, not a verified holding:** that an unhonoured retention promise is
> an FTC Act §5 / state UDAP exposure is a reasonable reading of how privacy promises are
> generally enforced — counsel should confirm.

**Questions:**
1. Review the exact erasure wording in the ToS, privacy notice, marketing site, and the
   heir-notification emails. Is it accurate against a purge + backup-retention horizon?
2. Since the deceased have no privacy rights here, **who** may enforce or waive the purge
   promise — the estate, the heirs, nobody?
3. Can a user contractually opt for longer retention (see §1)?

*Source: [GDPR Recital 27](https://gdpr-info.eu/recitals/no-27/).*

---

## 6. Retention schedule per data class — the ID scan problem

**Today:** one clock governs everything.

**Concern.** GDPR Art. 5(1)(e) and PIPEDA both expect a retention schedule with a
justification *per data class*, and our classes have very different defensible lifespans.
Most pointedly: a **government-ID scan is collected for a one-time identity check** and has
no business inheriting the will's retention. (Engineering note: Stripe holds those scans,
not us; the purge now requests their redaction, but the *right* answer is redacting shortly
after verification rather than at death.)

**Question:** approve a one-page retention schedule — will document, asset inventory, ID
scans, death certificates, video messages, payment records, audit logs — each with a period
and a written justification.

*Source: [GDPR Art. 5](https://gdpr-info.eu/art-5-gdpr/).*

---

## 7. Is a digital will even valid, and are we practising law?

The foundational questions, unresolved:

1. **Validity.** Is a will created and signed in this product legally valid in each US
   state and Canadian province — and in Saudi Arabia? What is required for execution
   (wet signature, witness presence, notarisation, remote-online-notarisation)? Our
   witnesses confirm by one-time code, remotely.
2. **Unauthorized practice of law.** We generate a testamentary instrument and compute
   Sharia inheritance shares. Where is the line between a document-preparation tool and
   the practice of law, and does our fara'id calculator cross it? What disclaimers or
   attorney-review step is required?
3. **Licensing.** Does operating this require any licence or registration in the launch
   markets?
4. **Unclaimed records.** If no heir ever comes forward, do escheat/abandoned-property
   rules apply to the records we hold?

---

## 8. Saudi Arabia — for the later phase (inverts the analysis)

**Finding:** PDPL **expressly covers the deceased**, unlike GDPR and CCPA. So in KSA the
purge is a *statutory duty owed in respect of a dead person*, and the surviving family's
identifiability arguably keeps the whole file in scope rather than releasing it. PDPL is
therefore the **strictest** of our three markets on precisely the operation this product is
built around — which is an argument for building the purge to the PDPL bar now rather than
retrofitting.

**Questions:** (1) Does Wasiati data count as **Sensitive Data** under PDPL — a Sharia will
arguably reveals religious belief, lineage records can surface parentage, death
certificates are health data? (2) What transfer basis (SCC equivalent) covers hosting
Saudi residents' data in Canada? (3) Confirm the destruction duty and any records-retention
period against SDAIA's own text.

> The retention figure circulating in practitioner summaries (five years for records of
> processing) could not be verified against SDAIA's primary text — **do not rely on it**
> without checking.

*Source: [ICLG Saudi Arabia data protection](https://iclg.com/practice-areas/data-protection-laws-and-regulations/saudi-arabia).*

---

## 9. Minor, but worth one line each

- **Canada:** PIPEDA has **no** federal "right to be deleted". Do not market one — the
  overclaim is its own misrepresentation risk. (OPC does expect a documented retention
  schedule and an inventory of where copies and backups live.)
- **The tombstone's legal home.** CCPA regs §7101 requires a 24-month log of deletion
  requests and responses, and Colorado explicitly permits keeping a deletion record "as
  needed to effectuate the deletion request" — which is the authority for our tombstone.
  It is also its **constraint**: §7101 forbids secondary use, so the tombstone must stay
  minimal (no names, no heir identities, no asset summary) and must not feed analytics.

*Sources: [OPC safeguarding guidance](https://www.priv.gc.ca/en/privacy-topics/business-privacy/breaches-and-safeguards/safeguarding-personal-information/gd_rd_201406/); [11 CCR 7101](https://www.law.cornell.edu/regulations/california/11-CCR-7101).*

---

## Priority for a first consultation

1. **§7 — validity and unauthorized practice of law.** Everything else is moot if the
   instrument is not valid or we cannot lawfully produce it.
2. **§2 — RUFADAA**, because it changes both the release flow *and* the designation UI.
3. **§1 + §3 — the retention clock and the court-lodging duty**, which together decide
   whether the 90-day purge survives in its current form.
4. **§5 — the wording review**, cheapest to fix and entirely within our control.
