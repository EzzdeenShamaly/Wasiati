import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/back_nav.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../commerce/application/entitlement_providers.dart';
import '../../files/presentation/video_messages_card.dart';
import '../../../core/network/api_exception.dart';
import '../../wills/application/wills_providers.dart';
import '../../wills/domain/wills_models.dart';
import '../../wills/domain/will_opening_text.dart';

/// Legacy messages (design 10b): a few words your family receives when your will is
/// released. The written message is live for everyone; Premium+ also get video
/// messages (upload today; webcam recording is a follow-up). Lower tiers see the
/// video soft-sell.
class LegacyMessagesScreen extends ConsumerWidget {
  const LegacyMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final wills = ref.watch(willsListProvider);

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 760;
          return SingleChildScrollView(
            // The bar's height rides on the content, so the video card slides under the
            // glass mid-scroll and still comes to rest clear of it.
            padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 28) +
                EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Reached from inside a will (_LegacyLink) and deliberately absent
                  // from the nav rail, so without this the only way out is the browser.
                  WasiatiBackLink(
                    label: context.l10n.wdBackToWills,
                    onTap: () => context.goBack('/wills'),
                  ),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Seal(size: 34, status: SealStatus.sealed),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.lgEyebrow,
                            style: TextStyle(color: context.tokens.goldInk, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                        const SizedBox(height: 2),
                        Text(l.lgTitle, style: t.headlineSmall),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(l.lgSubtitle, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
                  const SizedBox(height: 20),
                  wills.when(
                    loading: () => const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
                    error: (e, _) => _EmptyWill(message: l.lgLoadError),
                    data: (list) => list.isEmpty
                        ? _EmptyWill(message: l.lgCreateFirst)
                        : _WrittenMessageCard(will: list.first),
                  ),
                  const SizedBox(height: 16),
                  // Premium+ get the real video feature; everyone else the soft-sell.
                  if (entitlementHas(ref.watch(entitlementProvider).valueOrNull, 'videoMessages'))
                    const VideoMessagesCard()
                  else
                    const _VideoRoadmapCard(),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _WrittenMessageCard extends ConsumerStatefulWidget {
  final Will will;
  const _WrittenMessageCard({required this.will});
  @override
  ConsumerState<_WrittenMessageCard> createState() => _WrittenMessageCardState();
}

class _WrittenMessageCardState extends ConsumerState<_WrittenMessageCard> {
  late final TextEditingController _c = TextEditingController(text: widget.will.personalMessage ?? '');
  bool _busy = false;
  bool get _dirty => _c.text.trim() != (widget.will.personalMessage ?? '').trim();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Insert the optional Qur'an/Sunnah opening (locale-aware), sanitized to plain
  /// text. The user can then edit or clear it before saving.
  void _insertOpening(bool short) {
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    final text = sanitizePlainText(willOpeningText(arabic: arabic, short: short));
    setState(() {
      _c.text = text;
      _c.selection = TextSelection.collapsed(offset: _c.text.length);
    });
    WasiatiSnack.success(context, context.l10n.willOpeningInserted);
  }

  Future<void> _save() async {
    // No code in the will body: strip any markup/control chars before persisting.
    final clean = sanitizePlainText(_c.text).trim();
    setState(() => _busy = true);
    try {
      await ref.read(willsApiProvider).saveMessage(widget.will.id, clean);
      ref.invalidate(willsListProvider);
      ref.invalidate(willProvider(widget.will.id));
      if (mounted) WasiatiSnack.success(context, context.l10n.lgMessageSaved);
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final sealed = widget.will.status == 'SEALED';
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.edit_note_outlined,
              size: 20,
              color: Theme.of(context).brightness == Brightness.dark ? WasiatiColors.goldSoft : WasiatiColors.bottleGreen),
          const SizedBox(width: 8),
          Expanded(child: Text(l.lgWrittenMessage, style: t.titleMedium)),
          WasiatiChip(l.adminOfferLive, kind: WasiatiChipKind.region),
        ]),
        const SizedBox(height: 12),
        if (_c.text.trim().isEmpty) ...[
          _OpeningSuggestion(onInsert: _insertOpening),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _c,
          minLines: 4,
          maxLines: 12,
          maxLength: 5000, // spec §3 (DECISIONS §0)
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: l.lgHint,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text(
              sealed ? l.lgSealedNote : l.lgPrivateNote,
              style: t.bodySmall?.copyWith(color: context.tokens.faint),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: (!_dirty || _busy) ? null : _save,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.commonSave),
          ),
        ]),
      ]),
    );
  }
}

/// Offers the optional Islamic opening as an editable default (never auto-filled).
class _OpeningSuggestion extends StatelessWidget {
  final void Function(bool short) onInsert;
  const _OpeningSuggestion({required this.onInsert});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.greenDeep : WasiatiColors.greenTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.menu_book_outlined, size: 18, color: dark ? WasiatiColors.goldSoft : WasiatiColors.bottleGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l.willOpeningInsert,
                style: t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: dark ? WasiatiColors.goldSoft : WasiatiColors.bottleGreen)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(l.willOpeningSubtitle,
            style: t.bodySmall?.copyWith(
                color: dark ? WasiatiColors.darkTextMuted : WasiatiColors.greenDeep, height: 1.45)),
        const SizedBox(height: 10),
        Row(children: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 16)),
            onPressed: () => onInsert(false),
            child: Text(l.willOpeningFull),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 16)),
            onPressed: () => onInsert(true),
            child: Text(l.willOpeningShort),
          ),
        ]),
      ]),
    );
  }
}

class _VideoRoadmapCard extends StatelessWidget {
  const _VideoRoadmapCard();
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightSurface : WasiatiColors.parchment,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WasiatiColors.goldBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.videocam_outlined, size: 20, color: context.tokens.gold),
          const SizedBox(width: 8),
          Expanded(child: Text(l.lgVideoTitle, style: t.titleMedium)),
          WasiatiChip(l.lgVideoBadge, kind: WasiatiChipKind.lockedFeature),
        ]),
        const SizedBox(height: 8),
        Text(
          l.lgVideoBody,
          style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => WasiatiSnack.success(context, l.lgNotifySnack),
          icon: const Icon(Icons.notifications_none, size: 18),
          label: Text(l.lgNotifyButton),
        ),
      ]),
    );
  }
}

class _EmptyWill extends StatelessWidget {
  final String message;
  const _EmptyWill({required this.message});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
        const SizedBox(height: 14),
        FilledButton(onPressed: () => context.go('/wills/new'), child: Text(context.l10n.lgStartWill)),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => WasiatiCard(padding: const EdgeInsets.all(18), radius: 16, child: child);
}

