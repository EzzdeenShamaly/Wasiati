import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../application/content_providers.dart';
import '../data/content_api.dart';

/// The admin Console (design "Admin console"): a "Console" title + ADMIN pill and
/// the Plans · Promotions · Offers · Content tab bar. This screen is the **Content**
/// tab — the i18n content-key CMS (spec §7: edit user-facing strings EN + AR,
/// published live with a per-string audit trail) — under that console chrome; the
/// other tabs route to the commerce console at /admin.
class AdminContentScreen extends ConsumerWidget {
  const AdminContentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final list = ref.watch(contentListProvider);

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // Console title + ADMIN pill, with the CMS "add key" action.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
            child: Row(children: [
              Expanded(child: Text(l.adminConsoleTitle, style: t.headlineMedium)),
              IconButton(
                icon: const WasiatiIcon(svg: WasiatiIcons.add, size: 24),
                tooltip: l.adminContentAdd,
                onPressed: () => _edit(context, ref, null),
              ),
              const SizedBox(width: 4),
              const _AdminPill(),
            ]),
          ),
          const _ConsoleTabBar(),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: list.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(e is ApiException ? e.message : '$e', style: t.bodyMedium),
                  ),
                  data: (rows) => rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(l.adminContentEmpty,
                              textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
                        )
                      : ListView.separated(
                          // The bar's height rides on the content, so content-key rows slide under
                          // the glass mid-scroll and the last one still comes to rest clear of it.
                          padding: const EdgeInsets.all(20) +
                              EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _Row(row: rows[i], onEdit: () => _edit(context, ref, rows[i])),
                        ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, ContentString? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _EditSheet(existing: existing),
      ),
    );
    if (saved == true) ref.invalidate(contentListProvider);
  }
}

/// The inverted "ADMIN" chip beside the Console title (prototype: ink fill,
/// parchment text).
class _AdminPill extends StatelessWidget {
  const _AdminPill();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(color: WasiatiColors.inkNavy, borderRadius: BorderRadius.circular(99)),
      child: Text(
        context.l10n.adminConsolePill,
        style: const TextStyle(color: WasiatiColors.parchment, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.7),
      ),
    );
  }
}

/// Plans · Promotions · Offers · Content. Content is the active tab (this screen);
/// the commerce tabs route to the console at /admin.
class _ConsoleTabBar extends StatelessWidget {
  const _ConsoleTabBar();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    void goCommerce() => context.go('/admin');
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.tokens.hairline))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _tab(context, l.adminCommerceTabPlans, active: false, onTap: goCommerce),
          _tab(context, l.adminCommerceTabPromotions, active: false, onTap: goCommerce),
          _tab(context, l.adminCommerceTabOffers, active: false, onTap: goCommerce),
          _tab(context, l.adminContentTitle, active: true, onTap: null),
        ]),
      ),
    );
  }

  Widget _tab(BuildContext context, String label, {required bool active, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: active ? WasiatiColors.brassGold : Colors.transparent, width: 2.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            // The active tab label is type; bottleGreen made it the DIMMEST label
            // on the row in dark mode, inverting the selected/unselected reading.
            color: active ? context.tokens.greenInk : context.tokens.muted,
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.onEdit});
  final ContentString row;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.tokens.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.tokens.hairline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(row.key, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
            WasiatiChip(
              row.published ? l.adminContentPublished : l.adminContentDraft,
              kind: row.published ? WasiatiChipKind.region : WasiatiChipKind.admin,
            ),
          ]),
          const SizedBox(height: 6),
          Text(row.valueEn, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(row.valueAr,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
          ),
          if (row.updatedBy != null) ...[
            const SizedBox(height: 4),
            Text(
              context.digits(l.adminContentEditedBy(
                  row.updatedBy!, row.updatedAt?.toLocal().toString().split('.').first ?? '—')),
              style: t.bodySmall?.copyWith(color: context.tokens.faint),
            ),
          ],
        ]),
      ),
    );
  }
}

class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({required this.existing});
  final ContentString? existing;
  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  late final TextEditingController _key;
  late final TextEditingController _en;
  late final TextEditingController _ar;
  late final TextEditingController _note;
  late bool _published;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _key = TextEditingController(text: e?.key ?? '');
    _en = TextEditingController(text: e?.valueEn ?? '');
    _ar = TextEditingController(text: e?.valueAr ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _published = e?.published ?? true;
  }

  @override
  void dispose() {
    _key.dispose();
    _en.dispose();
    _ar.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    if (_key.text.trim().isEmpty || _en.text.trim().isEmpty || _ar.text.trim().isEmpty) {
      WasiatiSnack.danger(context, l.adminContentBothRequired);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(contentApiProvider).upsert(
            _key.text.trim(),
            en: _en.text.trim(),
            ar: _ar.text.trim(),
            note: _note.text.trim(),
            published: _published,
          );
      if (mounted) {
        WasiatiSnack.success(context, l.adminContentSaved);
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref.read(contentApiProvider).remove(_key.text.trim());
      if (mounted) {
        WasiatiSnack.success(context, context.l10n.adminContentRemoved);
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // A PICKER, not free text. The field used to accept any string, save it, and
          // answer 200 — but the app renders only keys a surface has opted into via
          // overrideText, so every other key was a silent no-op: edited, saved,
          // never shown, nothing reporting the mismatch. Offering only the honoured keys
          // makes what can be saved and what can be shown the same set.
          if (widget.existing == null)
            DropdownButtonFormField<String>(
              value: _key.text.isEmpty ? null : _key.text,
              decoration: InputDecoration(labelText: l.adminContentKey, helperText: l.adminContentKeyHelp),
              items: [
                for (final k in overridableKeys) DropdownMenuItem(value: k, child: Text(k)),
              ],
              onChanged: (v) => setState(() => _key.text = v ?? ''),
            )
          else
            // The key is the id — immutable once created.
            TextField(
              controller: _key,
              enabled: false,
              decoration: InputDecoration(labelText: l.adminContentKey),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _en,
            maxLines: null,
            decoration: InputDecoration(labelText: l.adminContentEn),
          ),
          const SizedBox(height: 12),
          Directionality(
            textDirection: TextDirection.rtl,
            child: TextField(
              controller: _ar,
              maxLines: null,
              decoration: InputDecoration(labelText: l.adminContentAr),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(labelText: l.adminContentNote),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _published,
            title: Text(l.adminContentPublished),
            onChanged: (v) => setState(() => _published = v),
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (widget.existing != null)
              TextButton(
                onPressed: _busy ? null : _remove,
                child: Text(l.adminContentRemove, style: TextStyle(color: context.tokens.dangerInk)),
              ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l.adminContentSave),
            ),
          ]),
        ]),
      ),
    );
  }
}
