import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/safe_launch.dart';
import '../../../core/network/api_exception.dart';
import '../../commerce/domain/commerce_models.dart' show formatMoney;
import '../application/zakat_providers.dart';
import '../domain/zakat_models.dart';

/// Zakat estimate (spec §5). Guidance, never a ruling — the warning is prominent and
/// unconditional, and the "Pay your zakah" button appears only when an admin has
/// published a vetted charity link.
class ZakatScreen extends ConsumerWidget {
  const ZakatScreen({super.key, this.from});

  /// The path zakat was opened from, supplied by the route as `?from=`. Null for a
  /// direct deep link. The router extracts it (as it does every other route
  /// parameter) so this screen stays renderable without a GoRouter above it.
  final String? from;

  /// Where "‹ Back" returns to. Entry points reach zakat with `context.go`, which
  /// REPLACES the stack — so there is nothing to pop and the AppBar shows no back
  /// button. The opener therefore passes `?from=<its own path>` and we walk back to
  /// it explicitly; a direct deep link (no `from`) falls back to the dashboard.
  ///
  /// The value is validated rather than trusted: only an in-app absolute path is
  /// honoured. A protocol-relative "//evil.example" or any absolute URL is dropped
  /// for the dashboard, so a crafted link can never point the breadcrumb off-app.
  static String backTarget(String? from) {
    final f = from?.trim() ?? '';
    if (!f.startsWith('/') || f.startsWith('//') || f.contains('://')) return '/dashboard';
    return f;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final estimate = ref.watch(zakatEstimateProvider);
    final target = backTarget(from);

    return Scaffold(
      appBar: AppBar(title: Text(l.zakatTitle)),
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          // The bar's height rides on the content, so the estimate panel slides under the
          // glass mid-scroll and the disclaimer still comes to rest clear of it.
          padding: const EdgeInsets.all(20) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Breadcrumb back to wherever zakat was opened from (assets, or the
                // dashboard for a deep link). Matches the assets/will-detail pattern.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: () => context.go(target),
                    child: Text(target.contains('/assets') ? l.zakatBackToAssets : l.zakatBackToDashboard),
                  ),
                ),
                const SizedBox(height: 6),
                estimate.when(
                  loading: () =>
                      const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
                  // A 503 here means no current gold price is configured. Say so plainly
                  // rather than showing a niṣāb we cannot stand behind.
                  error: (e, _) => _Card(
                    child: Text(
                      e is ApiException ? e.message : l.zakatUnavailable,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  data: (z) => _Body(z: z),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.z});
  final ZakatEstimate z;
  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  // Fixed dark rail-panel palette (prototype), independent of the app theme.
  static const _railBg = WasiatiColors.railGreen; // #24382F
  static const _railText = WasiatiColors.parchmentLight; // #F5EFE1
  static const _railMuted = WasiatiColors.darkTextMuted; // #9DB3A4
  static const _railLine = Color(0xFFCBD6CC); // breakdown labels
  static const _railGold = Color(0xFFC9A45E); // figures + pay fill
  static const _railInk = WasiatiColors.inkNavy; // pay-button ink #1C2333
  static const _railSuccess = Color(0xFF7FB89B); // "zakat is due" — legible green on the rail

  String _basisLabel(AppLocalizations l, String key) => switch (key) {
        'zakat.basis.cash' => l.zakatBasisCash,
        'zakat.basis.bank' => l.zakatBasisBank,
        'zakat.basis.shares' => l.zakatBasisShares,
        'zakat.basis.gold' => l.zakatBasisGold,
        _ => '',
      };

  String _hijriMonth(AppLocalizations l, int m) => switch (m) {
        1 => l.hijriMonth1,
        2 => l.hijriMonth2,
        3 => l.hijriMonth3,
        4 => l.hijriMonth4,
        5 => l.hijriMonth5,
        6 => l.hijriMonth6,
        7 => l.hijriMonth7,
        8 => l.hijriMonth8,
        9 => l.hijriMonth9,
        10 => l.hijriMonth10,
        11 => l.hijriMonth11,
        _ => l.hijriMonth12,
      };

  /// The ḥawl selects save immediately (the prototype's inline day/month controls),
  /// keeping whichever value the user did not just change.
  Future<void> _setHawl({required int day, required int month}) async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      await ref.read(zakatApiProvider).setHawl(day: day, month: month);
      ref.invalidate(zakatEstimateProvider);
      if (mounted) WasiatiSnack.success(context, l.zakatHawlSaved);
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One dark, translucent Hijri select styled for the rail panel.
  Widget _hawlSelect<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T> onChanged,
    required String semantic,
  }) {
    return Semantics(
      label: semantic,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0x1AECE3D0), // rgba(236,227,208,.10)
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x40ECE3D0)), // rgba(236,227,208,.25)
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            items: items,
            isDense: true,
            dropdownColor: WasiatiColors.greenDeep,
            iconEnabledColor: _railMuted,
            borderRadius: BorderRadius.circular(12),
            style: const TextStyle(color: _railText, fontSize: 12.5, fontWeight: FontWeight.w600),
            onChanged: _busy ? null : (v) => v == null ? null : onChanged(v),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final z = widget.z;
    // A display (Fraunces) style we shrink per-figure, keeping the Arabic fallback.
    final disp = Theme.of(context).textTheme.headlineMedium;
    String money(int minor) => formatMoney(minor, z.currency);
    final day = z.hawl?.day ?? 1;
    final month = z.hawl?.month ?? 1;

    // The whole estimate lives on one dark bottle-green rail panel (prototype):
    // light text, gold figures, an inline ḥawl control and the disclaimer inside.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(color: _railBg, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header: title + base on the left, the amount due in gold on the right.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.diamond_outlined, size: 26, color: _railGold),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.zakatTitle, style: const TextStyle(color: _railText, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(l.zakatSubtitle, style: const TextStyle(color: _railMuted, fontSize: 11.5, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(z.aboveNisab ? money(z.zakatDueMinor) : '—',
                style: disp?.copyWith(color: _railGold, fontSize: 26, fontWeight: FontWeight.w600)),
            Text(l.assetZakatCaption, style: const TextStyle(color: _railMuted, fontSize: 10.5)),
          ]),
        ]),
        const SizedBox(height: 14),

        // Inline ḥawl day/month selects.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0x0FECE3D0), // rgba(236,227,208,.06)
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.zakatHawl, style: const TextStyle(color: _railText, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(l.zakatHawlHijriOnly, style: const TextStyle(color: _railMuted, fontSize: 10.5, height: 1.5)),
              ]),
            ),
            const SizedBox(width: 12),
            _hawlSelect<int>(
              value: day,
              semantic: l.zakatHawlDay,
              // 1..30: no Hijri month has a 31st.
              items: [for (var d = 1; d <= 30; d++) DropdownMenuItem(value: d, child: Text('$d'))],
              onChanged: (d) => _setHawl(day: d, month: month),
            ),
            const SizedBox(width: 8),
            _hawlSelect<int>(
              value: month,
              semantic: l.zakatHawlMonth,
              items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(_hijriMonth(l, m)))],
              onChanged: (m) => _setHawl(day: day, month: m),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        // Per-category breakdown (label · fiqh basis · amount), then the totals.
        Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x26ECE3D0))), // rgba(236,227,208,.15)
          ),
          child: Column(children: [
            for (final c in z.categories)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 3,
                    child: Text(_categoryLabel(l, c.type), style: const TextStyle(color: _railLine, fontSize: 12)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: Text(_basisLabel(l, c.basisKey),
                        style: const TextStyle(color: _railMuted, fontSize: 10.5, height: 1.4)),
                  ),
                  const SizedBox(width: 10),
                  Text(money(c.totalMinor),
                      style: disp?.copyWith(color: _railText, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            // Zakatable-wealth total.
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0x26ECE3D0))),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(l.zakatBase,
                      style: const TextStyle(color: _railText, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                Text(money(z.zakatableTotalMinor),
                    style: disp?.copyWith(color: _railText, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ]),
            ),
            // Nisab threshold + above/below status.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(l.zakatNisab, style: const TextStyle(color: _railMuted, fontSize: 11.5))),
                Text(z.aboveNisab ? l.zakatDue : l.zakatNoneDue,
                    style: TextStyle(
                        color: z.aboveNisab ? _railSuccess : _railMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
            // Rate.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(l.zakatRate, style: const TextStyle(color: _railMuted, fontSize: 11.5))),
                const Text('× 2.5%', style: TextStyle(color: _railLine, fontSize: 11.5)),
              ]),
            ),
          ]),
        ),

        // What we deliberately left out. Never hidden.
        if (z.hasExcludedCrypto || z.unconverted.isNotEmpty) ...[
          const SizedBox(height: 10),
          if (z.hasExcludedCrypto)
            Text(l.zakatCryptoExcluded, style: const TextStyle(color: _railMuted, fontSize: 11, height: 1.5)),
          for (final u in z.unconverted) ...[
            const SizedBox(height: 4),
            Text(context.digits(l.zakatUnconverted(u.count, u.currency)),
                style: const TextStyle(color: _railMuted, fontSize: 11, height: 1.5)),
          ],
        ],

        // Gated: no published charity link means no button at all. Left-aligned,
        // auto-width, gold fill with dark ink and a trailing arrow (prototype).
        if (z.charityUrl != null && z.aboveNisab) ...[
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ElevatedButton(
              // https-only: the charity URL is set by a human admin via the Content console,
              // so it must not be trusted to carry a non-web (intent:/file:/js:) scheme.
              onPressed: _busy
                  ? null
                  : () async {
                      final ok = await safeLaunchExternal(z.charityUrl!);
                      if (!ok && context.mounted) WasiatiSnack.danger(context, context.l10n.settingsLinkError);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _railGold,
                foregroundColor: _railInk,
                elevation: 0,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(l.zakatPayNow, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                const Icon(Icons.north_east, size: 14),
              ]),
            ),
          ),
        ],

        const SizedBox(height: 14),
        // The disclaimer is unconditional and cannot be dismissed (spec §5).
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x1FC9A45E), // rgba(201,164,94,.12)
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x73C9A45E)), // rgba(201,164,94,.45)
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFE0C287)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l.zakatDisclaimer,
                  style: const TextStyle(color: Color(0xFFEADFC8), fontSize: 11.5, height: 1.65)),
            ),
          ]),
        ),
      ]),
    );
  }

  String _categoryLabel(AppLocalizations l, String type) => switch (type) {
        'CASH' => l.zakatCatCash,
        'BANK_ACCOUNT' => l.zakatCatBank,
        'SHARES' => l.zakatCatShares,
        'GOLD' => l.zakatCatGold,
        _ => type,
      };
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => WasiatiCard(child: child);
}
