import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/safe_launch.dart';
import '../../../core/providers.dart';
import '../../auth/domain/auth_state.dart';
import '../application/identity_providers.dart';

/// Identity verification (design 7b): status-aware. Verified shows the green
/// confirmation; otherwise a verify CTA (Nafath in KSA, document verification
/// elsewhere) beside the four-state reference list.
///
/// When no document-KYC vendor is configured the backend reports available=false
/// and 503s on session creation, so the CTA is disabled rather than offered and
/// then failed.
class KycScreen extends ConsumerStatefulWidget {
  const KycScreen({super.key});
  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> {
  bool _busy = false;

  String get _region {
    final auth = ref.read(authControllerProvider);
    return auth is AuthSignedIn ? auth.user.region : 'US';
  }

  Future<void> _verifyDocument() async {
    setState(() => _busy = true);
    try {
      final url = await ref.read(identityApiProvider).createSessionUrl();
      final ok = await safeLaunchExternal(url); // https-only: the KYC session URL comes from the backend
      if (!mounted) return;
      if (!ok) {
        WasiatiSnack.danger(context, context.l10n.settingsLinkError);
        return;
      }
      ref.invalidate(identityStatusProvider);
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
    final status = ref.watch(identityStatusProvider);
    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 780;
          return SingleChildScrollView(
            // The bar's height rides on the content, so the reference states slide under the
            // glass mid-scroll and the last one still comes to rest clear of it.
            padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 28) +
                EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(l.kycTitle, style: t.headlineMedium),
                  const SizedBox(height: 4),
                  Text(l.kycSubtitle, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
                  const SizedBox(height: 20),
                  status.when(
                    loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
                    error: (e, _) => _Panel(child: Text('${l.kycLoadError}\n$e', style: t.bodyMedium)),
                    data: (s) {
                      final verified = s.status == 'VERIFIED';
                      final statusCard = verified
                          ? const _VerifiedCard()
                          : _VerifyCard(
                              region: _region,
                              status: s.status,
                              available: s.available,
                              busy: _busy,
                              onVerify: _verifyDocument,
                              onNafath: () => WasiatiSnack.success(context, l.kycNafathSnack),
                            );
                      final states = _StatesList(current: s.status);
                      if (!wide) {
                        return Column(children: [statusCard, const SizedBox(height: 16), states]);
                      }
                      return IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(flex: 13, child: statusCard),
                          const SizedBox(width: 24),
                          Expanded(flex: 10, child: states),
                        ]),
                      );
                    },
                  ),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _VerifiedCard extends StatelessWidget {
  const _VerifiedCard();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return _Panel(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Seal(size: 84, status: SealStatus.verified, filled: true),
        const SizedBox(height: 16),
        Text(context.l10n.kycVerifiedTitle, style: t.titleLarge?.copyWith(color: context.tokens.successInk)),
        const SizedBox(height: 8),
        Text(context.l10n.kycVerifiedBody,
            textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
      ]),
    );
  }
}

class _VerifyCard extends StatelessWidget {
  final String region;
  final String status;
  final bool busy;
  final bool available;
  final VoidCallback onVerify;
  final VoidCallback onNafath;
  const _VerifyCard(
      {required this.region,
      required this.status,
      required this.available,
      required this.busy,
      required this.onVerify,
      required this.onNafath});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final pending = status == 'PENDING';
    final rejected = status == 'REJECTED';
    return _Panel(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Seal(size: 84, status: pending ? SealStatus.witnessed : (rejected ? SealStatus.rejected : SealStatus.idle), filled: pending || rejected),
        const SizedBox(height: 16),
        Text(
          pending ? l.kycInProgress : (rejected ? l.kycNeedsRetry : l.kycVerifyTitle),
          style: t.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          pending ? l.kycPendingBody : (rejected ? l.kycRejectedBody : l.kycVerifyBody),
          textAlign: TextAlign.center,
          style: t.bodyMedium?.copyWith(color: context.tokens.muted),
        ),
        const SizedBox(height: 22),
        if (region == 'KSA') ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(onPressed: onNafath, icon: const Text('ن', style: TextStyle(fontWeight: FontWeight.w700)), label: Text(l.kycVerifyNafath)),
          ),
          const SizedBox(height: 6),
          Text(l.kycNafathSub, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
          // The document rail is only offered when a vendor is actually configured.
          if (available) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: busy ? null : onVerify,
                child: busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(pending ? l.kycContinueVerification : l.kycVerifyDocument),
              ),
            ),
          ],
          // Prototype: the KSA build tells travellers that verification falls back to
          // Stripe Identity outside Saudi Arabia. Only meaningful before verifying.
          if (!pending && !rejected) ...[
            const SizedBox(height: 12),
            Text(l.kycOutsideNote, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: context.tokens.faint)),
          ],
        ] else if (available)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : onVerify,
              child: busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(pending ? l.kycContinueVerification : l.kycVerifyDocument),
            ),
          )
        else
          // No vendor wired: say so plainly rather than showing a button that 503s.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? WasiatiColors.nightSurface
                  : WasiatiColors.parchment,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(l.kycUnavailable,
                textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
          ),
      ]),
    );
  }
}

class _StatesList extends StatelessWidget {
  final String current;
  const _StatesList({required this.current});
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final rows = <({String key, SealStatus seal, String title, String sub})>[
      (key: 'UNVERIFIED', seal: SealStatus.idle, title: l.kycStateUnverified, sub: l.kycStateUnverifiedSub),
      (key: 'PENDING', seal: SealStatus.witnessed, title: l.kycStatePending, sub: l.kycStatePendingSub),
      (key: 'VERIFIED', seal: SealStatus.verified, title: l.kycStateVerified, sub: l.kycStateVerifiedSub),
      (key: 'REJECTED', seal: SealStatus.rejected, title: l.kycStateRejected, sub: l.kycStateRejectedSub),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l.kycAllStates,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: context.tokens.muted)),
      const SizedBox(height: 10),
      for (final r in rows)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
                color: r.key == current
                    ? WasiatiColors.brassGold
                    : (Theme.of(context).brightness == Brightness.dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
                width: r.key == current ? 1.6 : 1),
          ),
          child: Row(children: [
            Seal(size: 28, status: r.seal, filled: r.seal != SealStatus.idle),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.title, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(r.sub, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.nightRaised : WasiatiColors.parchmentLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dark ? WasiatiColors.darkBorder : WasiatiColors.outline),
      ),
      child: child,
    );
  }
}

