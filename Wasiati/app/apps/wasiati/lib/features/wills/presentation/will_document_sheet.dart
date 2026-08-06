import 'package:flutter/material.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

import '../../../core/l10n/l10n.dart';
import '../../assets/domain/asset_models.dart';
import '../domain/wills_models.dart';
import 'will_seal_marks.dart';

/// Type scale over the prototype's raw px values. 1.0 — the prototype's own
/// sizes — because the sheet is zoomed AS A WHOLE to fill its column (see
/// [WillDocumentSheet.build]), which is what actually makes it readable: at the
/// 60% column the effective body lands ~17px, the prototype at 133% browser
/// zoom. The 1.45 that briefly lived here predates the zoom working (a
/// FittedBox constraints bug kept the sheet at its natural 760px); once the
/// zoom engaged, the two multiplied to ~25px — "now the fonts are too big"
/// (owner, 27 Jul 2026). One knob does the scaling now, and it is the zoom.
const double _fz = 1.0;

/// The DV2.1 "Will export" sheet, rendered as LIVE Flutter widgets rather than a
/// rasterised PDF page (prototype lines 1685-1812).
///
/// This is the fix for "the prototype is much cleaner": the old in-app view showed
/// the server PDF through the `printing` package's PdfPreview — page bitmaps scaled
/// down to fit, so the type went soft and small. Here every glyph is native text at
/// its real size, so it reads exactly as crisply as the prototype's live HTML. The
/// authoritative artifact is still the server PDF (same design, same builder); the
/// preview card keeps a "Page view" toggle onto it, and the Download button hands
/// back that file — this widget never becomes the thing you keep, only the thing you
/// read. See [will-document.service.ts] for the parity target.
///
/// Sections, top to bottom (brief §1-7): the gold lock-seal header with the
/// bismillah; the boxed WORDS FOR MY FAMILY; FUNERAL & BURIAL WISHES; ASSETS &
/// LIABILITIES (table rows or narrative prose); DIVISION OF THE ESTATE with each
/// share's fiqh basis; (guardianship, when set); WITNESSES & TRUSTEE as a signature
/// grid; and the sealed rosette footer. It mirrors automatically in Arabic —
/// Directionality is inherited, digits localise, and the display face swaps to IBM
/// Plex Sans Arabic.
class WillDocumentSheet extends StatelessWidget {
  const WillDocumentSheet({
    super.key,
    required this.will,
    required this.assets,
    required this.witnesses,
    required this.trustees,
    required this.testatorName,
    required this.format,
    required this.display,
    this.city,
    this.country,
  });

  final Will will;
  final List<EstateAsset> assets;
  final List<Witness> witnesses;
  final List<Trustee> trustees;

  /// Derived the same way the server document is (`ownerEmail.split('@')[0]`) so the
  /// live sheet and the downloaded PDF name the testator identically — there is no
  /// name field on the user yet.
  final String testatorName;
  final String? city;
  final String? country;

  /// 'table' | 'essay' — how the estate reads. 'percent' | 'fraction' — how shares read.
  final String format;
  final String display;

  bool get _sealed => will.status == 'SEALED';

  /// The sheet is authored at the prototype's structural metrics (a 760px paper)
  /// with its type pre-enlarged by [_fz], and then zoomed further (FittedBox)
  /// only when the column is WIDER than the paper — so a big monitor gets a
  /// proportionally bigger sheet, never more empty parchment. Below the design
  /// width (the 60% column on a laptop, phones) the sheet lays out fluid at its
  /// native sizes — already readable thanks to [_fz] — instead of scaling DOWN,
  /// which would make things worse.
  static const double _designWidth = 760;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      if (!w.isFinite) return _sheet(context);
      if (w <= _designWidth) return SizedBox(width: w, child: _sheet(context));
      // The width wrapper is load-bearing: the parent column lays this out with
      // LOOSE constraints, and a FittedBox given loose constraints simply sits at
      // its child's natural 760px and never scales — which left the live document
      // smaller than the page view's PDF pages ("document view is showing smaller
      // than page size" — owner, 27 Jul 2026). Tight width forces the scale-up,
      // so both views fill the same column edge to edge.
      return SizedBox(
        width: w,
        child: FittedBox(
          fit: BoxFit.fitWidth,
          child: SizedBox(width: _designWidth, child: _sheet(context)),
        ),
      );
    });
  }

  Widget _sheet(BuildContext context) {
    final l = context.l10n;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final t = _DocTheme.of(context, isAr);

    return Container(
      // Paper: a crisper 6px radius and a 1px hairline instead of the app's soft
      // 18px cards, so it reads as a document, not a UI panel (brief).
      decoration: BoxDecoration(
        color: t.paper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.hair2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 60,
            offset: const Offset(0, 24),
            spreadRadius: -12,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, l, t),
          if (will.personalMessage?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 18),
            _words(context, l, t),
          ],
          ..._wishes(context, l, t),
          ..._estate(context, l, t),
          const SizedBox(height: 18),
          _division(context, l, t),
          ..._guardian(context, l, t),
          const SizedBox(height: 18),
          _signatures(context, l, t),
          const SizedBox(height: 22),
          _sealFooter(context, l, t),
        ],
      ),
    );
  }

  // --- (1) Header -----------------------------------------------------------
  Widget _header(BuildContext context, AppLocalizations l, _DocTheme t) {
    final place = [city?.trim(), _countryName(country, context)]
        .where((s) => s != null && s.isNotEmpty)
        .join(_isAr(context) ? '، ' : ', ');
    final testatorLine = l.wdocOf(testatorName) + (place.isEmpty ? '' : ' — $place');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.gold, width: 2))),
          child: Column(
            children: [
              const WillLockSeal(size: 52),
              const SizedBox(height: 10),
              Text('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontFamily: WasiatiType.arabicSerifFamily, fontSize: 18 * _fz, color: t.goldInk)),
              const SizedBox(height: 8),
              Text(_docTitle(l),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: t.displayFamily, fontSize: 23 * _fz, fontWeight: FontWeight.w600, color: t.ink)),
              const SizedBox(height: 4),
              Text(testatorLine,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: t.bodyFamily, fontSize: 12 * _fz, color: t.muted, height: 1.4)),
              const SizedBox(height: 4),
              Text(context.digits(_metaLine(context, l)),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: t.bodyFamily, fontSize: 11 * _fz, color: t.faint, height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }

  /// The document's own title — "Last Will & Testament" / "الوصية الأخيرة". Kept
  /// separate from [AppLocalizations.wdocTitle] (which is the page heading "Your
  /// will, as it will be read"): this is the words printed ON the paper.
  String _docTitle(AppLocalizations l) =>
      _isArLang(l) ? 'الوصية الأخيرة' : 'Last Will & Testament';

  String _metaLine(BuildContext context, AppLocalizations l) {
    // Dart's substring throws past the end (unlike JS slice, which the server uses),
    // and a will id is a UUID in production but can be shorter in tests/fixtures.
    final shortId = will.id.substring(0, will.id.length < 8 ? will.id.length : 8).toUpperCase();
    final willNo = l.wdocWillNumber(shortId);
    if (!_sealed) return '$willNo · ${l.wdocDraftSubtitle}';
    final confirmed = witnesses.where((w) => w.status.toUpperCase() == 'SIGNED').length;
    return [
      willNo,
      l.wdocSealedMeta(_formatDate(will.sealedAt, context)),
      l.wdocWitnessesConfirmed(confirmed),
    ].join(' · ');
  }

  // --- (2) Words for my family — the only boxed section ---------------------
  Widget _words(BuildContext context, AppLocalizations l, _DocTheme t) {
    return Container(
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.hair),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(l.wdocWordsTitle, t),
          const SizedBox(height: 4),
          Text('“${will.personalMessage!.trim()}”',
              style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 13 * _fz,
                  height: 1.7,
                  fontStyle: FontStyle.italic,
                  color: t.ink)),
        ],
      ),
    );
  }

  // --- (3) Funeral & burial wishes ------------------------------------------
  List<Widget> _wishes(BuildContext context, AppLocalizations l, _DocTheme t) {
    final f = will.funeralWishes;
    if (f == null) return const [];
    bool on(String k) => f[k] == true;
    final items = <String>[
      if (on('sunnah')) l.cwWish1,
      if (on('simple')) l.cwWish2,
      if (on('local')) l.cwWish3,
      on('azaa') ? l.cwWish4 : l.cwWish4No,
    ];
    return [
      const SizedBox(height: 18),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(l.wdocWishesTitle, t),
          const SizedBox(height: 6),
          Text(items.join(' · '),
              style: TextStyle(fontFamily: t.bodyFamily, fontSize: 12 * _fz, height: 1.7, color: t.body)),
        ],
      ),
    ];
  }

  // --- (4) Assets & liabilities — 2px gold top rule -------------------------
  List<Widget> _estate(BuildContext context, AppLocalizations l, _DocTheme t) {
    if (assets.isEmpty) return const [];
    return [
      const SizedBox(height: 18),
      _goldRuleSection(
        t,
        l.wdocEstateTitle,
        format == 'essay' ? _estateProse(context, l, t) : _estateTable(context, l, t),
        // The narrative already SAYS debts settle first, in the testator's own voice —
        // repeating it as a footnote would be the document annotating itself. The server
        // PDF drops it in essay mode for the same reason (its spec pins the absence).
        footnote: format == 'essay' ? null : l.wdocEstateNote,
      ),
    ];
  }

  List<Widget> _estateTable(BuildContext context, AppLocalizations l, _DocTheme t) {
    final rows = <Widget>[];
    Widget row({required String name, String? inst, String? amount, required bool loan, bool net = false}) {
      final content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!net) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: loan ? t.loanDot : t.assetDot, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: name,
                      style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 12.5 * _fz,
                          fontWeight: FontWeight.w700,
                          color: net ? t.goldInk : t.ink)),
                  if (inst != null)
                    TextSpan(
                        text: ' — $inst',
                        style: TextStyle(fontFamily: t.bodyFamily, fontSize: 12.5 * _fz, color: t.muted)),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            if (amount != null)
              Text(context.digits(amount),
                  style: TextStyle(
                      fontFamily: t.displayFamily,
                      fontSize: 12.5 * _fz,
                      fontWeight: net ? FontWeight.w700 : FontWeight.w600,
                      color: net ? t.greenInk : (loan ? t.dangerInk : t.ink))),
          ],
        ),
      );
      // A true DOTTED separator, as in the prototype (1px dotted hair2) — the
      // solid hairline this first shipped with was one of the "design elements
      // from prototype … fixed on the pdf version not on the page".
      return net ? content : Column(children: [content, _DottedDivider(color: t.hair2Dotted)]);
    }

    for (final a in assets.where((a) => !a.isLiability)) {
      rows.add(row(name: a.label, inst: a.institution, amount: a.valueLabel, loan: false));
    }
    for (final a in assets.where((a) => a.isLiability)) {
      rows.add(row(name: a.label, inst: a.institution, amount: a.signedValueLabel, loan: true));
    }
    for (final n in _netTotals()) {
      rows.add(const SizedBox(height: 2));
      // NET ESTATE, upper-case gold, exactly as the prototype prints it.
      rows.add(row(name: l.wdocNetEstate.toUpperCase(), amount: n, loan: false, net: true));
    }
    return rows;
  }

  List<Widget> _estateProse(BuildContext context, AppLocalizations l, _DocTheme t) {
    // The WILL LANGUAGE, not a re-flowed table. An earlier version of this method
    // joined the same rows with semicolons — "Villa — USD 2,100,000; …" — which
    // reads as an inventory printout and was the owner's exact complaint about the
    // Narrative view. These are the PDF's sentences (will-document.service.ts), so
    // the document on screen and the document that is kept say the same thing.
    Widget para(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(context.digits(s),
              textAlign: TextAlign.justify,
              style: TextStyle(fontFamily: t.bodyFamily, fontSize: 12.5 * _fz, height: 1.9, color: t.body)),
        );
    final owned = assets.where((a) => !a.isLiability).toList();
    final debts = assets.where((a) => a.isLiability).toList();

    // "Villa, held with Al Rajhi, valued at approximately USD 2,100,000" — each
    // clause appended only when the datum exists, exactly like the server document.
    String clause(EstateAsset a, String Function(String) withInst, String Function(String) withAmt) {
      final b = StringBuffer(a.label);
      if (a.institution != null) b.write(withInst(a.institution!));
      if (a.valueLabel != null) b.write(withAmt(a.valueLabel!));
      return b.toString();
    }

    // "a; b; and c" — localized separators (Arabic joins with ؛ / و).
    String joinItems(List<String> parts) => parts.length <= 1
        ? parts.join()
        : parts.sublist(0, parts.length - 1).join(l.wdocEssayListJoin) +
            l.wdocEssayListJoinLast +
            parts.last;

    final out = <Widget>[];
    if (owned.isNotEmpty) {
      final items = owned.map((a) => clause(a, l.wdocEssayHeldWith, l.wdocEssayValuedAt)).toList();
      out.add(para('${l.wdocEssayAssetsLead}${joinItems(items)}.'));
    }
    if (debts.isNotEmpty) {
      final items = debts.map((a) => clause(a, l.wdocEssayOwedTo, l.wdocEssayInAmount)).toList();
      out.add(para('${l.wdocEssayLiabilitiesLead}${joinItems(items)}.'));
    }
    final nets = _netTotals();
    if (nets.isNotEmpty) out.add(para(l.wdocEssayNetEstate(nets.join(l.wdocEssayNetJoin))));
    return out;
  }

  // --- (5) Division of the estate — 2px gold top rule -----------------------
  Widget _division(BuildContext context, AppLocalizations l, _DocTheme t) {
    final lang = Localizations.localeOf(context).languageCode;
    final rows = <Widget>[];
    if (will.shariaShares.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(l.wdocNoHeirs, style: TextStyle(fontFamily: t.bodyFamily, fontSize: 11 * _fz, color: t.faint)),
      ));
    }
    for (final s in will.shariaShares) {
      rows.add(_divRow(
        context,
        t,
        name: '${s.heirName} — ${heirRelLabel(l, s.heirRelation)}',
        basis: s.basisFor(lang) ?? '',
        share: _shareLabel(context, s.sharePercent),
        gold: false,
        last: s == will.shariaShares.last && will.bequests.isEmpty,
      ));
    }
    for (final b in will.bequests) {
      rows.add(_divRow(
        context,
        t,
        name: '${l.wdocBequest} — ${b.beneficiaryName}',
        basis: l.wdocBequestBasis,
        share: _percentLabel(context, b.sharePercent),
        gold: true,
        last: b == will.bequests.last,
      ));
    }
    return _goldRuleSection(t, l.wdocDivisionTitle, rows);
  }

  Widget _divRow(BuildContext context, _DocTheme t,
      {required String name, required String basis, required String share, required bool gold, required bool last}) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(name,
                  style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 13 * _fz,
                      fontWeight: FontWeight.w600,
                      color: gold ? t.goldInk : t.ink)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(basis,
                style: TextStyle(fontFamily: t.bodyFamily, fontSize: 11 * _fz, height: 1.4, color: t.faint)),
          ),
          const SizedBox(width: 10),
          Text(context.digits(share),
              style: TextStyle(
                  fontFamily: t.displayFamily,
                  fontSize: 13 * _fz,
                  fontWeight: FontWeight.w600,
                  color: gold ? t.goldInk : t.ink)),
        ],
      ),
    );
    // Dotted between rows, nothing after the last — the prototype's rhythm.
    return last ? content : Column(children: [content, _DottedDivider(color: t.hair2Dotted)]);
  }

  // --- Guardianship (when set) — hairline top rule --------------------------
  List<Widget> _guardian(BuildContext context, AppLocalizations l, _DocTheme t) {
    final mode = (will.guardianMode ?? '').trim().toLowerCase();
    if (mode != 'parent' && mode != 'islamic' && mode != 'named') return const [];
    final name = (will.guardianName ?? '').trim();
    if (mode == 'named' && name.isEmpty) return const [];

    final value = switch (mode) {
      'named' => name,
      'islamic' => l.cwGIslamicLbl,
      _ => l.cwGParentLbl,
    };
    final note = switch (mode) {
      'islamic' => l.cwGIslamicNote,
      'named' => l.cwGuardianNote,
      _ => l.cwGParentNote,
    };
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(value,
            style: TextStyle(fontFamily: t.bodyFamily, fontSize: 12.5 * _fz, fontWeight: FontWeight.w600, color: t.ink)),
      ),
    ];
    if (mode == 'named') {
      final phone = (will.guardianPhone ?? '').trim();
      final email = (will.guardianEmail ?? '').trim();
      final contact = [phone, email].where((s) => s.isNotEmpty).join(' · ');
      if (contact.isNotEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(contact,
              textDirection: TextDirection.ltr,
              style: TextStyle(fontFamily: t.bodyFamily, fontSize: 11 * _fz, color: t.goldInk)),
        ));
      }
    }
    rows.add(const SizedBox(height: 4));
    rows.add(Text(note, style: TextStyle(fontFamily: t.bodyFamily, fontSize: 10.5 * _fz, height: 1.5, color: t.faint)));

    return [
      const SizedBox(height: 18),
      _hairRuleSection(t, l.cwGuardTitle, rows),
    ];
  }

  // --- (6) Witnesses & trustee — hairline top rule, signature grid ----------
  Widget _signatures(BuildContext context, AppLocalizations l, _DocTheme t) {
    final wide = MediaQuery.sizeOf(context).width >= 640;

    Widget sig(
        {required String name,
        required String role,
        required bool signed,
        DateTime? date,
        String? contact,
        String pending = ''}) {
      // Each signature is dated with when THAT PERSON acted — witness.signedAt,
      // trustee.confirmedAt, the testator's own signedAt — matching the server's
      // renderer (will-document.service.ts). This used to stamp will.sealedAt on every
      // row, dating each signature with the one day nobody signed anything: on an
      // attestation page, who acted WHEN is the whole point of a date, and the person
      // relying on it is a probate clerk comparing this sheet against the PDF the
      // server rendered with the true dates.
      final meta = signed
          ? '$role · ${l.wdocSignedDigitally}${date != null ? ' · ${_formatDate(date, context)}' : ''}'
          : '$role · $pending';
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(signed ? name : '—',
                  style: TextStyle(
                      fontFamily: signed ? t.displayFamily : t.bodyFamily,
                      fontStyle: signed ? FontStyle.italic : FontStyle.normal,
                      fontSize: 19 * _fz,
                      color: signed ? t.ink : t.faint)),
            ),
            Container(
              padding: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: t.hair2))),
              child: Text(name,
                  style: TextStyle(fontFamily: t.bodyFamily, fontSize: 11.5 * _fz, fontWeight: FontWeight.w600, color: t.ink)),
            ),
            Text(context.digits(meta),
                style: TextStyle(fontFamily: t.bodyFamily, fontSize: 10 * _fz, color: t.faint)),
            if (contact != null && contact.isNotEmpty)
              Text(contact,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontFamily: t.bodyFamily, fontSize: 10 * _fz, color: t.goldInk)),
          ],
        ),
      );
    }

    Widget colLabel(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(s.toUpperCase(),
              style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 10 * _fz,
                  fontWeight: FontWeight.w700,
                  letterSpacing: _isAr(context) ? 0 : 0.6 * _fz,
                  color: t.faint)),
        );

    final witCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        colLabel(l.wdocWitnessesCol),
        if (witnesses.isEmpty)
          Text(l.wdocNoneRecorded, style: TextStyle(fontFamily: t.bodyFamily, fontSize: 10 * _fz, color: t.faint))
        else
          ...witnesses.map((w) => sig(
                name: w.fullName,
                role: l.wdocWitnessRole,
                signed: w.status.toUpperCase() == 'SIGNED',
                date: w.signedAt,
                pending: l.wdocPending,
              )),
      ],
    );

    final truCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        colLabel(l.wdocTrusteeCol),
        if (trustees.isEmpty)
          Text(l.wdocNoneRecorded, style: TextStyle(fontFamily: t.bodyFamily, fontSize: 10 * _fz, color: t.faint))
        else
          ...trustees.map((tr) {
            final confirmed = tr.status.toUpperCase() == 'CONFIRMED';
            return sig(
              name: tr.fullName,
              role: l.wdocTrusteeRole,
              signed: confirmed,
              date: tr.confirmedAt,
              pending: l.wdocPendingCode,
              contact: confirmed ? null : tr.phone,
            );
          }),
      ],
    );

    final grid = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: witCol),
              const SizedBox(width: 18),
              Expanded(child: truCol),
            ],
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [witCol, const SizedBox(height: 4), truCol]);

    // The server renderer's exact rule (will-document.service.ts): the testator has
    // signed once signedAt is set OR the will is sealed, and their date is when THEY
    // signed — falling back to the seal date only for wills sealed before signedAt was
    // recorded. Signing and sealing are separate acts, often days apart: the owner signs,
    // then witnesses sign, then the will seals.
    final testatorSigned = will.signedAt != null || _sealed;
    final testatorMeta = testatorSigned
        ? [
            l.wdocTestatorRole,
            l.wdocSignedDigitally,
            _formatDate(will.signedAt ?? will.sealedAt, context),
            if (city?.trim().isNotEmpty ?? false) city!.trim(),
          ].join(' · ')
        : '${l.wdocTestatorRole} · ${l.wdocPending}';

    return _hairRuleSection(t, l.wdocWitnessesTitle, [
      grid,
      const SizedBox(height: 8),
      // Testator signature — full width, larger, over a 1.5px ink rule.
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(testatorSigned ? testatorName : '—',
            style: TextStyle(
                fontFamily: testatorSigned ? t.displayFamily : t.bodyFamily,
                fontStyle: testatorSigned ? FontStyle.italic : FontStyle.normal,
                fontSize: 26 * _fz,
                color: testatorSigned ? t.ink : t.faint)),
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Container(
          padding: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: t.ink, width: 1.5))),
          child: Text(testatorName,
              style: TextStyle(fontFamily: t.bodyFamily, fontSize: 11.5 * _fz, fontWeight: FontWeight.w700, color: t.ink)),
        ),
      ),
      const SizedBox(height: 2),
      Text(context.digits(testatorMeta),
          style: TextStyle(fontFamily: t.bodyFamily, fontSize: 10.5 * _fz, color: t.faint)),
    ]);
  }

  // --- (7) Sealed footer ----------------------------------------------------
  Widget _sealFooter(BuildContext context, AppLocalizations l, _DocTheme t) {
    return Column(
      children: [
        if (_sealed) ...[
          const WillSealRosette(size: 120),
          const SizedBox(height: 10),
          Text(l.wdocSealLine,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: t.bodyFamily, fontSize: 12 * _fz, fontWeight: FontWeight.w700, color: t.ink)),
          const SizedBox(height: 4),
          Text(context.digits(_metaLine(context, l)),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: t.bodyFamily, fontSize: 10.5 * _fz, color: t.faint)),
          const SizedBox(height: 8),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Text(l.wdocGuidance,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: t.bodyFamily, fontSize: 10 * _fz, height: 1.5, color: t.faint)),
        ),
      ],
    );
  }

  // --- Section scaffolds ----------------------------------------------------
  Widget _sectionLabel(String text, _DocTheme t) => Text(
        text.toUpperCase(),
        style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 11 * _fz,
            fontWeight: FontWeight.w700,
            letterSpacing: t.isAr ? 0 : 0.77 * _fz, // .07em on 11px
            color: t.goldInk),
      );

  Widget _goldRuleSection(_DocTheme t, String label, List<Widget> children, {String? footnote}) {
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.gold, width: 2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(label, t),
          const SizedBox(height: 6),
          ...children,
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Text(footnote, style: TextStyle(fontFamily: t.bodyFamily, fontSize: 10.5 * _fz, height: 1.5, color: t.faint)),
          ],
        ],
      ),
    );
  }

  Widget _hairRuleSection(_DocTheme t, String label, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.hair))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(label, t),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  // --- Formatting helpers ---------------------------------------------------
  List<String> _netTotals() {
    final totals = <String, double>{};
    final curOf = <String, String?>{};
    for (final a in assets) {
      final v = a.estimatedValue;
      if (v == null) continue;
      final key = a.currency ?? '';
      totals[key] = (totals[key] ?? 0) + (a.isLiability ? -v : v);
      curOf[key] = a.currency;
    }
    return [
      for (final e in totals.entries)
        (curOf[e.key] == null ? '' : '${curOf[e.key]} ') + groupedAmount(e.value),
    ];
  }

  /// Fara'id share — the share's fraction when the toggle asks for it and one is
  /// clean, else the percentage. Mirrors the server's fractionLabel so the live
  /// sheet and the PDF agree on every share.
  String _shareLabel(BuildContext context, double percent) {
    if (display == 'fraction') {
      final f = _fractionLabel(percent);
      if (f != null) return f;
    }
    return _percentLabel(context, percent);
  }

  String _percentLabel(BuildContext context, double percent) {
    final whole = percent % 1 == 0;
    var s = '${whole ? percent.toStringAsFixed(0) : percent.toStringAsFixed(2)}%';
    if (_isAr(context)) s = s.replaceAll('.', '٫').replaceAll('%', '٪');
    return s;
  }

  /// The classical asl al-mas'ala denominators, ascending — a verbatim port of the
  /// prototype's fracOf (DV2.1 line 4115) and of the server's fractionLabel, so
  /// nearly every share flips visibly when the toggle does (12.5 → 1/8,
  /// 58.33 → 7/12, 29.17 → 7/24). Ascending order makes the first hit the
  /// simplest form; anything without a clean fraction falls back to %.
  static const List<int> _aslDenominators = [2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 96];
  String? _fractionLabel(double percent) {
    final target = percent / 100;
    for (final q in _aslDenominators) {
      final p = (target * q).round();
      if (p > 0 && p < q && (target - p / q).abs() < 0.0008) return '$p/$q';
    }
    return null;
  }

  String _formatDate(DateTime? d, BuildContext context) {
    if (d == null) return '—';
    final u = d.toUtc();
    final months = _isAr(context) ? _monthsAr : _monthsEn;
    return context.digits('${u.day} ${months[u.month - 1]} ${u.year}');
  }

  bool _isAr(BuildContext context) => Localizations.localeOf(context).languageCode == 'ar';
  bool _isArLang(AppLocalizations l) => l.localeName.startsWith('ar');

  String? _countryName(String? code, BuildContext context) {
    final c = (code ?? '').trim().toUpperCase();
    if (c.isEmpty) return null;
    return _countryNames[c] ?? c;
  }
}

const List<String> _monthsEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const List<String> _monthsAr = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// The four markets Wasiati sells in, plus a couple of common neighbours — enough
/// for the testator line without pulling in a full ICU region table.
const Map<String, String> _countryNames = {
  'SA': 'Kingdom of Saudi Arabia',
  'AE': 'United Arab Emirates',
  'QA': 'Qatar',
  'US': 'United States',
  'CA': 'Canada',
  'GB': 'United Kingdom',
  'KW': 'Kuwait',
  'BH': 'Bahrain',
  'OM': 'Oman',
  'EG': 'Egypt',
};

/// Resolved document palette. Text inks are the app's Ironclad tier (DECISIONS §22)
/// — readable in both themes — while the gold rule, green/danger dots and the seal
/// keep the prototype's brand fills, where contrast on a small mark does not matter.
class _DocTheme {
  final bool isAr;
  final String displayFamily;
  final String bodyFamily;
  final Color paper;
  final Color sunken;
  final Color ink;
  final Color body;
  final Color muted;
  final Color faint;
  final Color goldInk;
  final Color greenInk;
  final Color dangerInk;
  final Color gold;
  final Color hair;
  final Color hair2;
  final Color hair2Dotted;
  final Color assetDot;
  final Color loanDot;

  const _DocTheme({
    required this.isAr,
    required this.displayFamily,
    required this.bodyFamily,
    required this.paper,
    required this.sunken,
    required this.ink,
    required this.body,
    required this.muted,
    required this.faint,
    required this.goldInk,
    required this.greenInk,
    required this.dangerInk,
    required this.gold,
    required this.hair,
    required this.hair2,
    required this.hair2Dotted,
    required this.assetDot,
    required this.loanDot,
  });

  factory _DocTheme.of(BuildContext context, bool isAr) {
    final tokens = context.tokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Light theme pins the prototype's own --ink (#1C2333) rather than the app
    // theme's text colour, so the title, names and the family message read as the
    // near-black of the prototype sheet ("words for my family need to be black
    // like prototype font and color" — owner, 27 Jul 2026). Dark keeps the
    // theme's parchment ink — black on a night sheet would be unreadable.
    final ink = dark
        ? (Theme.of(context).textTheme.bodyMedium?.color ?? WasiatiColors.darkText)
        : const Color(0xFF1C2333);
    return _DocTheme(
      isAr: isAr,
      displayFamily: isAr ? WasiatiType.arabicFamily : WasiatiType.displayFamily,
      bodyFamily: isAr ? WasiatiType.arabicFamily : WasiatiType.bodyFamily,
      paper: tokens.card,
      sunken: dark ? WasiatiColors.nightRaised : WasiatiColors.parchment,
      ink: ink,
      body: dark ? WasiatiColors.darkTextMuted : WasiatiColors.onLightMuted,
      muted: tokens.muted,
      faint: tokens.faint,
      goldInk: tokens.goldInk,
      greenInk: tokens.greenInk,
      dangerInk: tokens.dangerInk,
      gold: const Color(0xFFA87B33), // brand gold rule — literal, both themes
      hair: tokens.hairline,
      hair2: dark ? const Color(0x33ECE3D0) : const Color(0x402F4A3D),
      hair2Dotted: dark ? const Color(0x22ECE3D0) : const Color(0x2E2F4A3D),
      assetDot: dark ? WasiatiColors.greenSoft : WasiatiColors.bottleGreen,
      loanDot: dark ? WasiatiColors.dangerSoft : WasiatiColors.danger,
    );
  }
}

/// The prototype's `1px dotted` row separator, drawn as 1×1 dots on a 3px rhythm —
/// Flutter borders have no dotted style, and the solid hairline that stood in for
/// it was a visible fidelity miss against the sheet's PDF twin.
class _DottedDivider extends StatelessWidget {
  const _DottedDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 1,
        child: CustomPaint(painter: _DottedLinePainter(color)),
      );
}

class _DottedLinePainter extends CustomPainter {
  const _DottedLinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double x = 0; x < size.width; x += 3) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) => oldDelegate.color != color;
}
