import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

import '../../../../core/l10n/l10n.dart';

/// "Confirm your email address before sealing", with the way to actually do it.
///
/// Shared by BOTH places a will can be sealed — the standalone Review & Seal screen and
/// step 6 of the create flow. It lived privately inside the former, so the create flow had
/// no notice at all: sealing there answered with a bare 400 snackbar and left the owner on
/// a dead screen, with the disclaimer ticked and a button that would never work, and no
/// hint that the fix was an email they had never opened.
///
/// The server is the gate (WillsService.seal asserts it). This is the entry point, which is
/// why callers default to "verified" while the check is loading or errors — a banner that
/// flickers on during a slow request would be worse than briefly absent, and the seal is
/// refused server-side regardless.
class VerifyEmailNotice extends StatelessWidget {
  /// Called when the owner comes back from /verify-email, so the fresh emailVerified check
  /// re-runs and a successful verification clears the banner.
  final VoidCallback onReturn;
  const VerifyEmailNotice({super.key, required this.onReturn});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? WasiatiColors.warningTintDark : WasiatiColors.warningTintLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WasiatiColors.warning),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.mark_email_unread_outlined, size: 16, color: context.tokens.warningInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l.rsVerifyEmailNotice,
                style: t.bodySmall?.copyWith(color: context.tokens.warningInk, height: 1.5)),
          ),
        ]),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: OutlinedButton(
            // push, not go: the owner returns to the review they came from, and onReturn
            // re-asks the server whether the address is confirmed now.
            onPressed: () => GoRouter.of(context).push('/verify-email').then((_) => onReturn()),
            child: Text(l.rsVerifyEmailCta),
          ),
        ),
      ]),
    );
  }
}
