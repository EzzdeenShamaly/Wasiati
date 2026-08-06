import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/back_nav.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../../auth/domain/auth_state.dart';
import '../../zakat/application/zakat_providers.dart';
import '../application/assets_providers.dart';
import '../domain/asset_models.dart';

/// Estate assets for a will (design 9a): the prototype's inventory TABLE —
/// asset · category · held with (masked account ref) · phone · email · value ·
/// status — split into Assets and Loans & liabilities, with an inline
/// "Add to the inventory" panel (Asset | Loan) instead of a popup dialog.
class AssetsScreen extends ConsumerStatefulWidget {
  final String willId;
  const AssetsScreen({super.key, required this.willId});
  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {
  // Inline add/edit panel (prototype 9a "Add to the inventory").
  bool _panelOpen = false;
  bool _loanMode = false;
  String _kind = 'CASH';
  String? _currency;
  bool _busy = false;
  // Inline validation messages. Null when the field is fine; the point is that a refusal
  // is always VISIBLE next to the input it concerns.
  String? _nameError;
  String? _valueError;
  String? _editingId; // non-null => the panel edits an existing item
  final _name = TextEditingController();
  final _heldWith = TextEditingController();
  final _value = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _ref = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _heldWith.dispose();
    _value.dispose();
    _phone.dispose();
    _email.dispose();
    _ref.dispose();
    super.dispose();
  }

  String get _region {
    final a = ref.read(authControllerProvider);
    return a is AuthSignedIn ? a.user.region : 'US';
  }

  void _openPanel({String? presetLabel, String? presetKind, EstateAsset? edit}) {
    setState(() {
      _panelOpen = true;
      _editingId = edit?.id;
      if (edit != null) {
        // Edit mode — prefill every field from the existing item.
        _loanMode = edit.isLiability;
        if (!edit.isLiability) _kind = edit.kind;
        _name.text = edit.label;
        _heldWith.text = edit.institution ?? '';
        _value.text = edit.estimatedValue == null ? '' : groupedAmount(edit.estimatedValue!);
        _phone.text = edit.contactPhone ?? '';
        _email.text = edit.contactEmail ?? '';
        _ref.text = edit.accountRef ?? '';
        if (edit.currency != null) _currency = edit.currency;
        return;
      }
      _loanMode = presetKind == 'LIABILITY';
      if (presetKind != null && presetKind != 'LIABILITY') _kind = presetKind;
      if (presetLabel != null && presetLabel.isNotEmpty) _name.text = presetLabel;
    });
  }

  void _closePanel() {
    setState(() {
      _panelOpen = false;
      _editingId = null;
      _nameError = null;
      _valueError = null;
      _name.clear();
      _heldWith.clear();
      _value.clear();
      _phone.clear();
      _email.clear();
      _ref.clear();
    });
  }

  Future<void> _submit() async {
    final label = _name.text.trim();
    if (label.isEmpty) {
      // This used to `return` silently. Pressing Add did nothing at all — no error, no
      // message, no movement — which reads as "I can't add assets", not "you missed a
      // field". A control that refuses without saying why is indistinguishable from a
      // broken one, and that is exactly how it got reported.
      setState(() => _nameError = context.l10n.asNameRequired);
      return;
    }
    if (_value.text.trim().isNotEmpty && double.tryParse(_value.text.trim().replaceAll(',', '')) == null) {
      // Same failure shape, quieter: an unparseable amount silently became null and the
      // asset saved with no value at all.
      setState(() => _valueError = context.l10n.asValueInvalid);
      return;
    }
    setState(() {
      _nameError = null;
      _valueError = null;
    });
    setState(() => _busy = true);
    try {
      final api = ref.read(assetsApiProvider);
      final kind = _loanMode ? 'LIABILITY' : _kind;
      final value = double.tryParse(_value.text.trim().replaceAll(',', ''));
      final currency = _currency ?? assetCurrencies(_region).first;
      if (_editingId != null) {
        await api.update(
          _editingId!,
          label: label,
          kind: kind,
          estimatedValue: value,
          currency: currency,
          institution: _heldWith.text.trim(),
          contactPhone: _phone.text.trim(),
          contactEmail: _email.text.trim(),
          accountRef: _ref.text.trim(),
        );
      } else {
        await api.add(
          widget.willId,
          label: label,
          kind: kind,
          estimatedValue: value,
          currency: currency,
          institution: _heldWith.text.trim(),
          contactPhone: _phone.text.trim(),
          contactEmail: _email.text.trim(),
          accountRef: _ref.text.trim(),
        );
      }
      ref.invalidate(assetsProvider(widget.willId));
      _closePanel();
    } catch (e) {
      if (mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The prototype's "Export to Excel": fetch the owner-scoped CSV and save it.
  Future<void> _exportCsv() async {
    try {
      final bytes = await ref.read(assetsApiProvider).exportCsv(widget.willId);
      await FileSaver.instance.saveFile(
        name: 'wasiati-inventory',
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
    } catch (e) {
      if (mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    }
  }

  Future<void> _delete(String id) async {
    try {
      await ref.read(assetsApiProvider).delete(widget.willId, id);
      ref.invalidate(assetsProvider(widget.willId));
    } catch (e) {
      if (mounted) WasiatiSnack.danger(context, '$e'.replaceFirst('ApiException: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final region = _region;
    final assets = ref.watch(assetsProvider(widget.willId));
    final groups = assetSuggestions(l, region);

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 860;
          return SingleChildScrollView(
            // The bar's height rides on the content, so asset rows and cards slide under
            // the glass mid-scroll and the vault note still comes to rest clear of it.
            padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 28) +
                EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Breadcrumb back to the owning will — assets are a sub-page of it.
                  WasiatiBackLink(
                    label: l.commonBackToWill,
                    // Step 4's "Edit assets & loans" PUSHES this screen, so popping puts
                    // the owner back on the step mid-form. go() replaced it and lost the will.
                    onTap: () => context.goBack('/wills/${widget.willId}'),
                  ),
                  const SizedBox(height: 6),
                  // header
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.assetEyebrow,
                            style: TextStyle(
                                color: context.tokens.goldInk,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6)),
                        const SizedBox(height: 4),
                        Text(l.assetTitle, style: t.headlineSmall),
                        const SizedBox(height: 4),
                        Text(l.assetSubtitle, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    // Actions wrap to a second line on tight widths rather than overflowing.
                    Flexible(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _exportCsv,
                            icon: const WasiatiIcon(svg: WasiatiIcons.download, size: 18),
                            label: Text(l.assetExport),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _openPanel(presetKind: 'LIABILITY'),
                            icon: const WasiatiIcon(svg: WasiatiIcons.add, size: 18),
                            label: Text(l.assetAddLoan),
                          ),
                          FilledButton.icon(
                            onPressed: () => _openPanel(),
                            icon: const WasiatiIcon(svg: WasiatiIcons.add, size: 18),
                            label: Text(l.assetAddButton),
                          ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  // inline add panel — prototype's "Add to the inventory"
                  if (_panelOpen) ...[
                    _addPanel(context, wide),
                    const SizedBox(height: 20),
                  ],
                  // suggestion chips prefill the panel
                  for (final g in groups) ...[
                    Text(g.heading,
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: context.tokens.muted)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 9, runSpacing: 9, children: [
                      for (final s in g.items)
                        _SuggestionChip(
                          label: s.label,
                          liability: s.kind == 'LIABILITY',
                          onTap: () => _openPanel(presetLabel: s.label, presetKind: s.kind),
                        ),
                    ]),
                    const SizedBox(height: 16),
                  ],
                  Text(l.assetRegionNote, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
                  const SizedBox(height: 20),
                  // inventory — table on wide, cards on narrow
                  assets.when(
                    loading: () =>
                        const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
                    error: (e, _) => Text(l.assetErrorHint, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
                    data: (list) {
                      if (list.isEmpty) {
                        return Text(l.assetEmptyHint, style: t.bodyMedium?.copyWith(color: context.tokens.muted));
                      }
                      final realAssets = [for (final a in list) if (!a.isLiability) a];
                      final loans = [for (final a in list) if (a.isLiability) a];
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (wide)
                          _InventoryTable(
                              assets: realAssets, loans: loans, onDelete: _delete, onEdit: (a) => _openPanel(edit: a))
                        else ...[
                          if (realAssets.isNotEmpty) ...[
                            _sectionLabel(context, l.assetSectionAssets),
                            const SizedBox(height: 10),
                            for (final a in realAssets)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _AssetCard(
                                    asset: a, onDelete: () => _delete(a.id), onEdit: () => _openPanel(edit: a)),
                              ),
                            const SizedBox(height: 4),
                          ],
                          if (loans.isNotEmpty) ...[
                            _sectionLabel(context, l.assetSectionLoans),
                            const SizedBox(height: 10),
                            for (final a in loans)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _AssetCard(
                                    asset: a, onDelete: () => _delete(a.id), onEdit: () => _openPanel(edit: a)),
                              ),
                            const SizedBox(height: 4),
                          ],
                        ],
                        const SizedBox(height: 14),
                        _TotalsBar(assets: realAssets, loans: loans),
                      ]);
                    },
                  ),
                  const SizedBox(height: 18),
                  // Zakat is computed from exactly these assets, so the estimate
                  // banner lives here (prototype) and opens the full calculation.
                  _ZakatBanner(willId: widget.willId),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? WasiatiColors.greenDeep
                          : WasiatiColors.greenTint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      l.assetVaultNote,
                      style: t.bodySmall?.copyWith(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? WasiatiColors.goldSoft
                              : WasiatiColors.bottleGreen,
                          height: 1.5),
                    ),
                  ),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }

  // --- the inline "Add to the inventory" panel ------------------------------

  Widget _addPanel(BuildContext context, bool wide) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final currencies = assetCurrencies(_region);
    final currency = _currency ?? currencies.first;
    // Loan mode pins the kind to LIABILITY; asset mode offers the catalog.
    const assetKinds = ['CASH', 'BANK', 'REAL_ESTATE', 'SHARES', 'GOLD', 'CRYPTO', 'PENSION', 'VEHICLE', 'BUSINESS', 'OTHER'];

    Widget field(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.muted)),
          const SizedBox(height: 6),
          child,
        ]);

    final name = field(
        l.assetFieldName,
        TextField(
          controller: _name,
          decoration: InputDecoration(hintText: l.assetHintName, errorText: _nameError),
          onChanged: (_) => _nameError == null ? null : setState(() => _nameError = null),
        ));
    final heldWith = field(_loanMode ? l.assetFieldLender : l.assetFieldHeldWith,
        TextField(controller: _heldWith, decoration: InputDecoration(hintText: l.assetHintHeldWith)));
    final category = field(
      l.assetFieldCategory,
      DropdownButtonFormField<String>(
        value: _loanMode ? 'LIABILITY' : _kind,
        items: [
          if (_loanMode)
            DropdownMenuItem(value: 'LIABILITY', child: Text(assetKindLabel(l, 'LIABILITY')))
          else
            for (final k in assetKinds) DropdownMenuItem(value: k, child: Text(assetKindLabel(l, k))),
        ],
        onChanged: _loanMode ? null : (v) => setState(() => _kind = v ?? 'CASH'),
      ),
    );
    final valueCur = field(
      l.assetFieldValueCurrency,
      Row(children: [
        Expanded(
          child: TextField(
            controller: _value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(hintText: l.assetHintValue, errorText: _valueError),
            onChanged: (_) => _valueError == null ? null : setState(() => _valueError = null),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: DropdownButtonFormField<String>(
            value: currency,
            items: currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _currency = v),
          ),
        ),
      ]),
    );
    final phone = field(l.assetFieldPhone, TextField(controller: _phone, decoration: InputDecoration(hintText: l.assetHintPhone)));
    final email = field(l.assetFieldEmail, TextField(controller: _email, decoration: InputDecoration(hintText: l.assetHintEmail)));
    final refField =
        field(l.assetFieldAccountRef, TextField(controller: _ref, decoration: InputDecoration(hintText: l.assetHintAccountRef)));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(_editingId != null ? l.assetInvEditTitle : l.assetInvTitle,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
          // Asset | Loan segmented toggle
          _ModeChip(label: l.assetInvAsset, selected: !_loanMode, onTap: () => setState(() => _loanMode = false)),
          const SizedBox(width: 8),
          _ModeChip(label: l.assetInvLoan, selected: _loanMode, onTap: () => setState(() => _loanMode = true)),
        ]),
        const SizedBox(height: 16),
        if (wide) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: name),
            const SizedBox(width: 14),
            Expanded(flex: 3, child: heldWith),
            const SizedBox(width: 14),
            Expanded(flex: 3, child: category),
            const SizedBox(width: 14),
            Expanded(flex: 4, child: valueCur),
          ]),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: phone),
            const SizedBox(width: 14),
            Expanded(child: email),
          ]),
          const SizedBox(height: 14),
          refField,
        ] else ...[
          name,
          const SizedBox(height: 12),
          heldWith,
          const SizedBox(height: 12),
          category,
          const SizedBox(height: 12),
          valueCur,
          const SizedBox(height: 12),
          phone,
          const SizedBox(height: 12),
          email,
          const SizedBox(height: 12),
          refField,
        ],
        const SizedBox(height: 12),
        Text(l.assetRefHelper, style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5)),
        const SizedBox(height: 4),
        Text(l.assetCurrencyHelper, style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.5)),
        const SizedBox(height: 16),
        Row(children: [
          FilledButton(
            // Disabled only while a save is in flight — NOT when the form is incomplete.
            //
            // This also disabled on an empty name, and nothing said so. The name is the
            // first of eight fields, so an owner who filled in the value, the bank and the
            // account reference met a dead button with no explanation. That is what "I
            // can't add assets" was: not a failing request, a control that refused to be
            // pressed. Pressing it now runs _submit, which names the field that is missing.
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_editingId != null ? l.commonSave : l.commonAdd),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: _closePanel, child: Text(l.commonCancel)),
        ]),
      ]),
    );
  }
}

/// Asset | Loan segmented chip for the panel header.
class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? WasiatiColors.bottleGreen
                : (dark ? WasiatiColors.nightSurface : WasiatiColors.parchment),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? WasiatiColors.bottleGreen : context.tokens.hairline),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? WasiatiColors.parchmentLight : context.tokens.muted)),
        ),
      ),
    );
  }
}

// --- the inventory table (wide layout) --------------------------------------

class _InventoryTable extends StatelessWidget {
  final List<EstateAsset> assets;
  final List<EstateAsset> loans;
  final void Function(String id) onDelete;
  final void Function(EstateAsset asset) onEdit;
  const _InventoryTable({required this.assets, required this.loans, required this.onDelete, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rows = <Widget>[];
    rows.add(_headerRow(context));
    for (var i = 0; i < assets.length; i++) {
      rows.add(_row(context, assets[i], zebra: i.isOdd));
    }
    if (loans.isNotEmpty) {
      rows.add(_bandRow(context, l.assetSectionLoans));
      for (var i = 0; i < loans.length; i++) {
        rows.add(_row(context, loans[i], zebra: i.isOdd));
      }
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: Column(children: rows),
    );
  }

  static const _flexes = (asset: 22, category: 12, heldWith: 18, phone: 13, email: 17, value: 13, status: 9);

  Widget _headerRow(BuildContext context) {
    final l = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget h(String s, int flex, {bool end = false}) => Expanded(
          flex: flex,
          child: Text(s,
              textAlign: end ? TextAlign.end : TextAlign.start,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: context.tokens.muted)),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: dark ? WasiatiColors.nightSurface : WasiatiColors.parchmentDeep,
      child: Row(children: [
        h(l.assetColAsset, _flexes.asset),
        h(l.assetColCategory, _flexes.category),
        h(l.assetColHeldWith, _flexes.heldWith),
        h(l.assetColPhone, _flexes.phone),
        h(l.assetColEmail, _flexes.email),
        h(l.assetColValue, _flexes.value, end: true),
        h(l.assetColStatus, _flexes.status, end: true),
        const SizedBox(width: 64),
      ]),
    );
  }

  Widget _bandRow(BuildContext context, String label) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: dark ? WasiatiColors.nightSurface : WasiatiColors.parchmentDeep,
      child: Text(label,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: context.tokens.muted)),
    );
  }

  Widget _row(BuildContext context, EstateAsset a, {required bool zebra}) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = t.bodySmall?.copyWith(color: context.tokens.muted);
    final dash = Text('—', style: muted);
    final valueColor = a.isLiability ? context.tokens.dangerInk : (dark ? WasiatiColors.parchmentLight : WasiatiColors.inkNavy);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: zebra ? (dark ? WasiatiColors.nightSurface : WasiatiColors.parchment) : Colors.transparent,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          flex: _flexes.asset,
          child: Row(children: [
            Text(assetKindEmoji(a.kind), style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Expanded(child: Text(a.label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
          ]),
        ),
        Expanded(
          flex: _flexes.category,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: a.isLiability
                    ? (dark ? WasiatiColors.warningTintDark : WasiatiColors.warningTintLight)
                    : (dark ? WasiatiColors.greenDeep : WasiatiColors.greenTint),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(assetKindLabel(l, a.kind),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      // The tint behind this stays raw; only the type on it moves.
                      color: a.isLiability
                          ? context.tokens.warningInk
                          : (dark ? WasiatiColors.goldSoft : WasiatiColors.bottleGreen))),
            ),
          ),
        ),
        Expanded(
          flex: _flexes.heldWith,
          child: (a.institution == null || a.institution!.isEmpty)
              ? dash
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.institution!, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (a.maskedRef != null) Text(a.maskedRef!, style: muted?.copyWith(fontSize: 11)),
                ]),
        ),
        Expanded(
          flex: _flexes.phone,
          child: (a.contactPhone == null || a.contactPhone!.isEmpty)
              ? dash
              : Text(a.contactPhone!, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          flex: _flexes.email,
          child: (a.contactEmail == null || a.contactEmail!.isEmpty)
              ? dash
              : Text(a.contactEmail!, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          flex: _flexes.value,
          child: Text(a.signedValueLabel ?? '—',
              textAlign: TextAlign.end,
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: valueColor)),
        ),
        Expanded(
          flex: _flexes.status,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 7, height: 7, decoration: BoxDecoration(color: context.tokens.warningInk, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(l.assetStatusManual,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.tokens.warningInk)),
          ]),
        ),
        SizedBox(
          width: 64,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                fixedSize: const Size(30, 30),
                minimumSize: const Size(30, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const WasiatiIcon(svg: WasiatiIcons.edit, size: 17),
              onPressed: () => onEdit(a),
            ),
            IconButton(
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                fixedSize: const Size(30, 30),
                minimumSize: const Size(30, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.delete_outline, size: 17),
              onPressed: () => onDelete(a.id),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final bool liability;
  final VoidCallback onTap;
  const _SuggestionChip({required this.label, required this.liability, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = liability
        ? (dark ? WasiatiColors.warningTintDark : WasiatiColors.warningTintLight)
        : (dark ? WasiatiColors.greenDeep : WasiatiColors.greenTint);
    final fg = liability ? context.tokens.warningInk : (dark ? WasiatiColors.goldSoft : WasiatiColors.bottleGreen);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
          child: Text('+ $label', style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  final EstateAsset asset;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  const _AssetCard({required this.asset, required this.onDelete, required this.onEdit});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final icon = switch (asset.kind) {
      'REAL_ESTATE' => Icons.home_outlined,
      'BANK' => Icons.account_balance_outlined,
      'PENSION' => Icons.savings_outlined,
      'VEHICLE' => Icons.directions_car_outlined,
      'BUSINESS' => Icons.storefront_outlined,
      'LIABILITY' => Icons.request_quote_outlined,
      _ => Icons.inventory_2_outlined,
    };
    final accent = asset.isLiability ? context.tokens.warningInk : (dark ? WasiatiColors.goldSoft : WasiatiColors.bottleGreen);
    final metaParts = [
      assetKindLabel(context.l10n, asset.kind),
      if (asset.institution?.isNotEmpty == true) asset.institution!,
      if (asset.maskedRef != null) asset.maskedRef!,
      if (asset.notes?.isNotEmpty == true) asset.notes!,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: dark ? WasiatiColors.greenDeep : WasiatiColors.greenTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(asset.label, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(metaParts.join(' · '),
                style: t.bodySmall?.copyWith(color: context.tokens.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (asset.signedValueLabel != null) ...[
          const SizedBox(width: 8),
          Text(asset.signedValueLabel!, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: accent)),
        ],
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const WasiatiIcon(svg: WasiatiIcons.edit, size: 19),
          onPressed: onEdit,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: onDelete,
        ),
      ]),
    );
  }
}

Widget _sectionLabel(BuildContext context, String text) => Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.muted),
    );

/// Net-estate footer: total assets − total loans, grouped by currency so a
/// mixed-currency estate still totals correctly. Debts settle before the shares.
class _TotalsBar extends StatelessWidget {
  final List<EstateAsset> assets;
  final List<EstateAsset> loans;
  const _TotalsBar({required this.assets, required this.loans});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final assetByCur = <String, double>{};
    final loanByCur = <String, double>{};
    for (final x in assets) {
      final v = x.estimatedValue;
      if (v != null) assetByCur[x.currency ?? ''] = (assetByCur[x.currency ?? ''] ?? 0) + v;
    }
    for (final x in loans) {
      final v = x.estimatedValue;
      if (v != null) loanByCur[x.currency ?? ''] = (loanByCur[x.currency ?? ''] ?? 0) + v;
    }
    final currencies = (<String>{...assetByCur.keys, ...loanByCur.keys}).toList()..sort();
    if (currencies.isEmpty) return const SizedBox.shrink(); // nothing valued yet

    String fmt(String cur, double v) {
      final n = groupedAmount(v);
      return cur.isEmpty ? n : '$cur $n';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel(context, l.assetTotalsTitle),
        const SizedBox(height: 12),
        for (final cur in currencies) ...[
          Row(children: [
            Expanded(
              child: Text('${l.assetTotalAssets}: ${fmt(cur, assetByCur[cur] ?? 0)}',
                  style: t.bodySmall?.copyWith(color: context.tokens.muted)),
            ),
            if ((loanByCur[cur] ?? 0) > 0)
              Text('− ${fmt(cur, loanByCur[cur] ?? 0)}',
                  style: t.bodySmall?.copyWith(color: context.tokens.warningInk, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: Text(l.assetNetEstate, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
            Text(fmt(cur, (assetByCur[cur] ?? 0) - (loanByCur[cur] ?? 0)),
                style: t.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800, color: context.tokens.goldInk)),
          ]),
          if (cur != currencies.last) const Divider(height: 20),
        ],
      ]),
    );
  }
}

/// Dark-green zakat strip (prototype): gold seal, "Zakat estimate" + hawl
/// sub-line on the left, the estimated amount due in gold on the right.
/// The whole banner opens the full calculation; on a load error it still
/// navigates, showing an em-dash instead of the amount.
class _ZakatBanner extends ConsumerWidget {
  const _ZakatBanner({required this.willId});

  /// Passed to zakat as `?from=` so its "‹ Back" breadcrumb returns here. `go`
  /// replaces the stack, so without this the zakat screen has nothing to pop back to.
  final String willId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final estimate = ref.watch(zakatEstimateProvider);
    final amountStyle = t.headlineSmall?.copyWith(color: WasiatiColors.goldSoft, fontWeight: FontWeight.w800);

    return Material(
      // Fixed dark bottle-green rail (prototype), same in light and dark.
      color: WasiatiColors.railGreen,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go(
            Uri(path: '/zakat', queryParameters: {'from': '/wills/$willId/assets'}).toString()),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            const Icon(Icons.diamond_outlined, size: 22, color: WasiatiColors.goldSoft),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.assetZakatTitle,
                    style: const TextStyle(color: WasiatiColors.onDark, fontSize: 14.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(l.assetZakatSubline,
                    style: const TextStyle(color: WasiatiColors.darkTextMuted, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 12),
            estimate.when(
              loading: () => const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: WasiatiColors.goldSoft)),
              error: (e, _) => Text('—', style: amountStyle),
              data: (z) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  z.aboveNisab ? '${z.currency} ${groupedAmount(z.zakatDueMinor / 100)}' : '—',
                  style: amountStyle,
                ),
                Text(l.assetZakatCaption,
                    style: const TextStyle(color: WasiatiColors.darkTextMuted, fontSize: 11)),
              ]),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.expand_more, size: 20, color: WasiatiColors.darkTextMuted),
          ]),
        ),
      ),
    );
  }
}
