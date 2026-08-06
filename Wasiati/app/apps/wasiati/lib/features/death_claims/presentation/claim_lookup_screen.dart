import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../application/claim_providers.dart';
import '../../auth/presentation/widgets/auth_scaffold.dart';

/// `/claim` — the public way in.
///
/// Two free-text contacts: the person who has died, and your own. Both may be an
/// email or a phone; the server discriminates on '@'.
///
/// THE ACKNOWLEDGEMENT IS NOT A RESULT. The backend answers 202
/// `{ acknowledged: true }` identically for an unknown person, a person with no
/// sealed will, a claimant who is not a party, and a full match — that uniformity is
/// the entire point of the endpoint, and this screen must not undo it by phrasing
/// success as "we found them". The copy says only what is true in every case: if a
/// will exists, the people named on it have been told.
///
/// Uses AuthScaffold(centered: true) so it reads as a sibling of the portal card.
class ClaimLookupScreen extends ConsumerStatefulWidget {
  const ClaimLookupScreen({super.key});

  @override
  ConsumerState<ClaimLookupScreen> createState() => _ClaimLookupScreenState();
}

class _ClaimLookupScreenState extends ConsumerState<ClaimLookupScreen> {
  final _deceased = TextEditingController();
  final _claimant = TextEditingController();

  @override
  void dispose() {
    _deceased.dispose();
    _claimant.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(claimLookupControllerProvider);
    final ctrl = ref.read(claimLookupControllerProvider.notifier);
    final t = Theme.of(context).textTheme;

    if (state.acknowledged) {
      return AuthScaffold(
        title: l.pcAckTitle,
        subtitle: l.pcAckBody,
        centered: true,
        showBack: false,
        children: [
          FilledButton(
            onPressed: () => context.go('/portal'),
            child: Text(l.pcAckClose),
          ),
        ],
      );
    }

    return AuthScaffold(
      title: l.pcLookupTitle,
      subtitle: l.pcLookupSub,
      centered: true,
      onBack: () => context.go('/portal'),
      children: [
        _FieldLabel(l.pcDeceasedLbl),
        const SizedBox(height: 6),
        TextField(
          controller: _deceased,
          onChanged: ctrl.setDeceased,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(hintText: l.pcDeceasedPh, labelText: l.pcDeceasedLbl),
        ),
        const SizedBox(height: 18),
        _FieldLabel(l.pcClaimantLbl),
        const SizedBox(height: 6),
        TextField(
          controller: _claimant,
          onChanged: ctrl.setClaimant,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(hintText: l.pcClaimantPh, labelText: l.pcClaimantLbl),
        ),
        if (state.error != null) ...[
          const SizedBox(height: 14),
          Text(localizedApiMessage(l, state.error!), style: t.bodySmall?.copyWith(color: context.tokens.dangerInk)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 48, // >= 44px touch target (spec §7)
          child: FilledButton(
            onPressed: state.canSubmit ? ctrl.submit : null,
            child: state.busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.pcLookupBtn),
          ),
        ),
      ],
    );
  }
}

/// The prototype's small-caps field label.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        // The label is repeated as the field's own labelText for screen readers,
        // so the painted caption is decoration.
        excludeSemantics: true,
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.tokens.muted,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}
