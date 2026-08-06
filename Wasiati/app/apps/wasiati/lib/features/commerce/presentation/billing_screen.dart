import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/config/env.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/safe_launch.dart';
import '../application/commerce_providers.dart';
import '../domain/commerce_models.dart';

/// Manage billing (spec §2, prototype's `billingOpen` panel): current plan +
/// renewal, payment method with a change-card action, invoices with PDF, and the
/// cancel link.
///
/// We are the billing portal — our own engine runs the billing cycle and we
/// deliberately do not use Stripe Billing, so there is no hosted portal to send
/// people to. Everything here except the card itself is ours, which is why the
/// page stays truthful on an environment with no Stripe keys: it shows the plan,
/// the renewal and the invoices, and simply states that card management is off.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});
  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  String? _busyInvoiceId;
  bool _busyAction = false;

  Future<void> _guard(Future<void> Function() run) async {
    setState(() => _busyAction = true);
    try {
      await run();
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _changeCard() => _guard(() async {
        final url = await ref.read(paymentsApiProvider).changeCardUrl(
              successUrl: Env.cardChangeSuccessUrl,
              cancelUrl: Env.cardChangeCancelUrl,
            );
        // https-only: the URL comes from the backend, which got it from the PSP.
        final ok = await safeLaunchExternal(url);
        if (!ok && mounted) WasiatiSnack.danger(context, context.l10n.settingsLinkError);
      });

  Future<void> _downloadInvoice(Invoice invoice) async {
    setState(() => _busyInvoiceId = invoice.id);
    try {
      final bytes = await ref.read(paymentsApiProvider).invoicePdf(invoice.id);
      await Printing.sharePdf(bytes: bytes, filename: 'wasiati-invoice-${invoice.id}.pdf');
    } on ApiException catch (e) {
      if (mounted) WasiatiSnack.danger(context, e.message);
    } catch (_) {
      if (mounted) WasiatiSnack.danger(context, context.l10n.billingInvoiceError);
    } finally {
      if (mounted) setState(() => _busyInvoiceId = null);
    }
  }

  Future<void> _cancel() async {
    final l = context.l10n;
    // Cancelling is destructive and irreversible-feeling; say plainly what does and
    // does not happen before doing it.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.billingCancelConfirmTitle),
        content: Text(l.billingCancelConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.billingCancelConfirmKeep)),
          OutlinedButton(
            style: WasiatiButtons.destructive(ctx),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.prBillingCancelSub),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _guard(() async {
      await ref.read(paymentsApiProvider).cancelSubscription();
      ref.invalidate(billingProvider);
      if (mounted) WasiatiSnack.success(context, l.billingCancelled);
    });
  }

  Future<void> _resume() => _guard(() async {
        await ref.read(paymentsApiProvider).resumeSubscription();
        ref.invalidate(billingProvider);
        if (mounted) WasiatiSnack.success(context, context.l10n.billingResumed);
      });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final billing = ref.watch(billingProvider);

    return Scaffold(
      // bottom: false — the shell's frosted bar overlaps the body, and its height is
      // spent on the scroll padding below instead (see AppShell's extendBody).
      body: SafeArea(
        bottom: false,
        child: billing.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.billingLoadError, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
            ),
          ),
          data: (b) => LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 760;
            return SingleChildScrollView(
              // The bar's height rides on the content, so the invoice rows slide under the
              // glass mid-scroll and the cancel row still comes to rest clear of it.
              padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 28) +
                  EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(l.billingTitle, style: t.headlineMedium),
                    const SizedBox(height: 4),
                    Text(l.billingSubtitle, style: t.bodyMedium?.copyWith(color: context.tokens.muted)),
                    const SizedBox(height: 20),
                    if (!b.hasSubscription)
                      _NoPlanCard(onSeePlans: () => context.go('/pricing'))
                    else ...[
                      // Plan + payment method, side by side on a wide screen
                      // (prototype: auto-fit minmax(180px, 1fr)).
                      _TwoUp(
                        wide: wide,
                        first: _PlanCard(billing: b),
                        second: _PaymentMethodCard(
                          billing: b,
                          busy: _busyAction,
                          onChangeCard: _changeCard,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _InvoicesCard(
                        invoices: b.invoices,
                        busyInvoiceId: _busyInvoiceId,
                        onDownload: _downloadInvoice,
                      ),
                      const SizedBox(height: 16),
                      _FooterRow(
                        cancelling: b.cancelAtPeriodEnd,
                        busy: _busyAction,
                        onCancel: _cancel,
                        onResume: _resume,
                      ),
                    ],
                  ]),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Two cards side by side when there is room, stacked when there isn't.
class _TwoUp extends StatelessWidget {
  final bool wide;
  final Widget first;
  final Widget second;
  const _TwoUp({required this.wide, required this.first, required this.second});

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return Column(children: [first, const SizedBox(height: 12), second]);
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ]),
    );
  }
}

/// A small uppercase section label — prototype's 10.5px/700/.05em faint caption.
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: context.tokens.faint,
        ),
      );
}

class _PlanCard extends StatelessWidget {
  final BillingOverview billing;
  const _PlanCard({required this.billing});

  /// Dates are shown as a plain ISO day: this is a billing record, and an
  /// unambiguous date beats a prettily-localized one that can be misread.
  static String _day(DateTime? d) => d == null ? '—' : d.toIso8601String().substring(0, 10);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final cancelling = billing.cancelAtPeriodEnd;
    // The server sends `status`, and this card never read it. A PAST_DUE subscriber —
    // whose renewal already FAILED — was shown "Renews <a past date> · <price>": a
    // promise about a charge that had already been declined, on the one screen where
    // they could still fix the card before the dunning cron gives up and cancels them.
    // PAST_DUE means currentPeriodEnd is behind us, so the same date now reads as what
    // it really is: the day the payment failed.
    final pastDue = billing.status == 'PAST_DUE';
    final price = billing.planPriceLabel;
    final date = _day(billing.currentPeriodEnd);

    return WasiatiCard(
      padding: const EdgeInsets.all(16),
      radius: 14,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _FieldLabel(l.billingCurrentPlan),
        const SizedBox(height: 4),
        Text(billing.planDisplayName ?? billing.tier ?? '—',
            style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(
          pastDue
              ? context.digits(l.billingPastDueLine(date))
              : cancelling
                  ? context.digits(l.billingEndsOn(date))
                  // Only promise a price when we actually have the live one.
                  : (price == null
                      ? context.digits(l.billingRenewsOnPlain(date))
                      : context.digits(l.billingRenewsOn(date, price))),
          style: t.bodySmall?.copyWith(color: pastDue ? context.tokens.warningInk : context.tokens.muted),
        ),
        if (pastDue) ...[
          const SizedBox(height: 6),
          Text(l.billingPastDueHelp,
              style: t.bodySmall?.copyWith(color: context.tokens.warningInk, height: 1.4)),
        ] else if (cancelling) ...[
          const SizedBox(height: 6),
          Text(l.billingCancelling,
              style: t.bodySmall?.copyWith(color: context.tokens.warningInk, height: 1.4)),
        ],
      ]),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final BillingOverview billing;
  final bool busy;
  final VoidCallback onChangeCard;
  const _PaymentMethodCard({required this.billing, required this.busy, required this.onChangeCard});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    // What we can honestly say, in descending order of knowledge: the real card,
    // "a card is saved" (stored but not describable), or "no card".
    final cardLine = billing.card?.label ?? (billing.hasPaymentMethod ? l.billingCardOnFile : l.billingNoCard);

    return WasiatiCard(
      padding: const EdgeInsets.all(16),
      radius: 14,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _FieldLabel(l.billingPaymentMethod),
        const SizedBox(height: 4),
        Text(cardLine, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        if (billing.canChangeCard)
          TextButton(
            onPressed: busy ? null : onChangeCard,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: AlignmentDirectional.centerStart,
            ),
            child: Text(l.billingChangeCard,
                style: t.bodySmall?.copyWith(color: context.tokens.goldInk, fontWeight: FontWeight.w600)),
          )
        else
          // No provider keys: say so rather than offering a button that can only fail.
          Text(l.billingCardUnavailable, style: t.bodySmall?.copyWith(color: context.tokens.faint, height: 1.4)),
      ]),
    );
  }
}

class _InvoicesCard extends StatelessWidget {
  final List<Invoice> invoices;
  final String? busyInvoiceId;
  final ValueChanged<Invoice> onDownload;
  const _InvoicesCard({required this.invoices, required this.busyInvoiceId, required this.onDownload});

  static String _day(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;

    return WasiatiCard(
      padding: const EdgeInsets.all(16),
      radius: 14,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _FieldLabel(l.billingInvoices),
        const SizedBox(height: 8),
        if (invoices.isEmpty)
          Text(l.billingNoInvoices, style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5))
        else
          for (final inv in invoices)
            _InvoiceRow(
              invoice: inv,
              busy: busyInvoiceId == inv.id,
              onDownload: () => onDownload(inv),
              day: _day(inv.issuedAt),
            ),
      ]),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final Invoice invoice;
  final bool busy;
  final VoidCallback onDownload;
  final String day;
  const _InvoiceRow({required this.invoice, required this.busy, required this.onDownload, required this.day});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final refunded = invoice.refunded;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.tokens.hairline)),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(day, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              Text(invoice.description,
                  style: t.bodySmall?.copyWith(color: context.tokens.faint, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 10),
          Text(invoice.amountLabel, style: t.bodySmall?.copyWith(color: context.tokens.muted)),
          const SizedBox(width: 10),
          Text(
            refunded ? l.billingRefunded : l.billingPaid,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: refunded ? context.tokens.warningInk : context.tokens.successInk,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 46,
            child: busy
                ? const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton(
                    onPressed: onDownload,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('PDF',
                        style: t.bodySmall?.copyWith(color: context.tokens.goldInk, fontWeight: FontWeight.w600)),
                  ),
          ),
        ]),
        // A part-credit invoice must not read as if the card paid the whole thing.
        if (invoice.paidWithCredit)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                context.digits(l.billingCreditApplied(formatMoney(invoice.creditAppliedMinor, invoice.currency))),
                style: t.bodySmall?.copyWith(color: context.tokens.faint, fontSize: 11),
              ),
            ),
          ),
      ]),
    );
  }
}

class _FooterRow extends StatelessWidget {
  final bool cancelling;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onResume;
  const _FooterRow({required this.cancelling, required this.busy, required this.onCancel, required this.onResume});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(l.billingProviderNote,
              style: t.bodySmall?.copyWith(color: context.tokens.faint, fontSize: 11, height: 1.5)),
        ),
        if (cancelling)
          // Reuses the existing subscription-action keys (prBillingResume /
          // prBillingCancelSub) rather than minting near-duplicates.
          FilledButton(onPressed: busy ? null : onResume, child: Text(l.prBillingResume))
        else
          TextButton(
            onPressed: busy ? null : onCancel,
            child: Text(l.prBillingCancelSub,
                style: t.bodySmall?.copyWith(color: context.tokens.dangerInk, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}

class _NoPlanCard extends StatelessWidget {
  final VoidCallback onSeePlans;
  const _NoPlanCard({required this.onSeePlans});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return WasiatiCard(
      padding: const EdgeInsets.all(24),
      radius: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.billingNoPlanTitle, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(l.billingNoPlanBody, style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5)),
        const SizedBox(height: 14),
        FilledButton(onPressed: onSeePlans, child: Text(l.billingSeePlans)),
      ]),
    );
  }
}
