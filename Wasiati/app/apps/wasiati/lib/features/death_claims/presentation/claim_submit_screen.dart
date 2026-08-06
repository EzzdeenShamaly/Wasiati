import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/presentation/widgets/auth_scaffold.dart';
import '../../files/domain/file_models.dart';
import '../application/claim_providers.dart';

/// `/claim/:token` — the invite landing.
///
/// The token arrives as a PATH SEGMENT, not a query string, which keeps the
/// credential out of access logs, Referer headers and browser history. It is read
/// off the path here and re-sent as the X-Claim-Token header; it is never put in a
/// form field and never stored.
///
/// willId, role and phone are NOT collected: all three come off the token, and the
/// backend strips anything else from the body. This screen therefore asks for
/// exactly two things — a name and the death certificate.
class ClaimSubmitScreen extends ConsumerStatefulWidget {
  const ClaimSubmitScreen({super.key, required this.token});
  final String token;

  @override
  ConsumerState<ClaimSubmitScreen> createState() => _ClaimSubmitScreenState();
}

class _ClaimSubmitScreenState extends ConsumerState<ClaimSubmitScreen> {
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Check the link before offering the form. A dead link used to surface only when the
    // presign fired — after the name was typed and a photograph had been read into memory.
    // Deferred one frame: the controller emits, and a Notifier must not be written to
    // during the build that first reads it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(claimSubmitControllerProvider.notifier).checkLink(widget.token);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: deathCertificateExtensions,
      withData: true, // the bytes are PUT straight to storage
    );
    final file = res?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    // Both checks happen BEFORE presign, and each has its own message: a claimant
    // told "the certificate is needed" when the real problem is a 20 MB scan has
    // no way to work out what to do next. They also protect the token's storage
    // budget — a refused presign is refunded, but only after a round trip.
    final ct = deathCertificateContentType(file.extension);
    if (ct == null) {
      messenger.showSnackBar(SnackBar(content: Text(l.pcCertBadType)));
      return;
    }
    if (bytes.length > deathCertificateMaxBytes) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.pcCertTooLarge(formatBytes(deathCertificateMaxBytes)))),
      );
      return;
    }

    await ref.read(claimSubmitControllerProvider.notifier).attachCertificate(
          token: widget.token,
          fileName: file.name,
          contentType: ct,
          bytes: Uint8List.fromList(bytes),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final state = ref.watch(claimSubmitControllerProvider);
    final ctrl = ref.read(claimSubmitControllerProvider.notifier);

    if (state.step == ClaimSubmitStep.checking) {
      return AuthScaffold(
        title: l.pcInviteTitle,
        subtitle: l.pcInviteSub,
        centered: true,
        showBack: false,
        children: const [Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))],
      );
    }

    // A dead link is a dead end, not a form error: nothing to correct, nothing to retry.
    // Say so, and point at the one thing that still works — starting again. This copy was
    // written and translated into both locales and had never been rendered.
    if (state.step == ClaimSubmitStep.linkDead) {
      return AuthScaffold(
        title: l.pcLinkInvalidTitle,
        subtitle: l.pcLinkInvalidSub,
        centered: true,
        showBack: false,
        children: [
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => context.go('/claim'),
            child: Text(l.pcStartOver),
          ),
        ],
      );
    }

    if (state.step == ClaimSubmitStep.done) {
      return AuthScaffold(
        title: l.pcDoneTitle,
        subtitle: l.pcDoneSub,
        centered: true,
        showBack: false,
        children: const [],
      );
    }

    return AuthScaffold(
      title: l.pcInviteTitle,
      subtitle: l.pcInviteSub,
      centered: true,
      showBack: false,
      children: [
        Text(
          l.pcNameLbl,
          style: t.labelSmall?.copyWith(color: tokens.muted, letterSpacing: 0.6, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _name,
          onChanged: ctrl.setName,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: InputDecoration(hintText: l.pcNamePh, labelText: l.pcNameLbl),
        ),
        const SizedBox(height: 24),

        // --- Death certificate: REQUIRED -------------------------------------
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.raised,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tokens.hairline),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.pcCertTitle, style: t.titleSmall),
            const SizedBox(height: 4),
            Text(l.pcCertSub, style: t.bodySmall?.copyWith(color: tokens.muted)),
            const SizedBox(height: 14),
            // ONE certificate per link, and the UI must not pretend otherwise.
            // ClaimAccessToken.uploadCount is capped at CLAIM_UPLOAD_OPERATION_CAP
            // = 2, and one presign + one confirm spends both. Only a FAILED presign
            // is refunded. So once a certificate is confirmed, a "choose a different
            // file" button could only ever burn a request and come back with "This
            // link has already been used to send a document." Offering it to someone
            // who has just realised they attached the wrong scan would be cruel, so
            // the attach control is replaced by the honest way out.
            if (state.certificate != null) ...[
              Row(children: [
                Icon(Icons.check_circle_outline, size: 20, color: tokens.successInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.pcCertAttached(state.certificateName ?? ''),
                    style: t.bodySmall?.copyWith(color: tokens.successInk, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(l.pcCertOnce, style: t.bodySmall?.copyWith(color: tokens.faint, height: 1.5)),
            ] else
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: state.uploading ? null : _pick,
                  icon: state.uploading
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.attach_file, size: 18),
                  label: Text(state.uploading ? l.pcCertUploading : l.pcCertChoose),
                ),
              ),
          ]),
        ),

        if (state.error != null) ...[
          const SizedBox(height: 14),
          Text(localizedApiMessage(l, state.error!), style: t.bodySmall?.copyWith(color: tokens.dangerInk)),
        ],

        const SizedBox(height: 22),
        SizedBox(
          height: 48,
          child: FilledButton(
            // Disabled until a certificate is actually confirmed — it is required,
            // and submitting without one only produces a 400 the claimant cannot act on.
            onPressed: state.canSubmit ? () => ctrl.submit(widget.token) : null,
            child: state.busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.pcSubmitBtn),
          ),
        ),
        if (state.certificate == null) ...[
          const SizedBox(height: 8),
          Text(l.pcCertRequired,
              textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: tokens.faint)),
        ],
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => context.go('/portal'),
            style: TextButton.styleFrom(foregroundColor: tokens.faint),
            child: Text(l.portalTitle),
          ),
        ),
      ],
    );
  }
}
