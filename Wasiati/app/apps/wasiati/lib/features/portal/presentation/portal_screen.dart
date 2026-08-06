import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// intl exports its own `TextDirection` class, which shadows dart:ui's enum and
// breaks `TextDirection.rtl` on the Qur'anic line below. Only the date formatter
// is needed here.
import 'package:intl/intl.dart' show DateFormat;
import 'package:printing/printing.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/safe_launch.dart';
import '../../../core/widgets/code_cells.dart';
import '../../assets/domain/asset_models.dart' show assetKindFromType;
import '../../auth/presentation/widgets/auth_scaffold.dart';
import '../application/portal_providers.dart';
import '../domain/portal_models.dart';

/// `/portal` — the heir & trustee portal, all three steps in ONE route.
///
/// One route, not three, because the session token must never reach the URL: a
/// `/portal/view?token=…` would put a live bearer credential into browser history,
/// the Referer header of every outbound link, and any shared-device autocomplete.
/// The step is state, and the address bar stays `/portal` throughout.
///
/// `?role=heir|trustee` preselects the segment. It is a PREFILL ONLY and grants
/// nothing — the recipient still does email → code.
class PortalScreen extends ConsumerStatefulWidget {
  const PortalScreen({super.key, this.roleParam});
  final String? roleParam;

  @override
  ConsumerState<PortalScreen> createState() => _PortalScreenState();
}

class _PortalScreenState extends ConsumerState<PortalScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(portalControllerProvider.notifier).prefillRole(widget.roleParam);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(portalControllerProvider);
    return switch (state.step) {
      PortalStep.signIn => _SignIn(emailController: _email),
      PortalStep.code => _CodeStep(controller: _code, focusNode: _codeFocus),
      PortalStep.view => const _PortalView(),
    };
  }
}

// --- Step 1: role + email ----------------------------------------------------

class _SignIn extends ConsumerWidget {
  const _SignIn({required this.emailController});
  final TextEditingController emailController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final state = ref.watch(portalControllerProvider);
    final ctrl = ref.read(portalControllerProvider.notifier);

    return AuthScaffold(
      title: l.portalTitle,
      subtitle: l.portalSub,
      centered: true,
      showBack: false,
      children: [
        // The prototype's two-up role segment.
        Row(children: [
          Expanded(
            child: _RoleButton(
              label: l.portalRoleHeir,
              selected: state.role == PortalRole.heir,
              onTap: () => ctrl.setRole(PortalRole.heir),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _RoleButton(
              label: l.portalRoleTrustee,
              selected: state.role == PortalRole.trustee,
              onTap: () => ctrl.setRole(PortalRole.trustee),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: emailController,
          onChanged: ctrl.setEmail,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          onSubmitted: (_) => state.canContinue ? ctrl.requestCode() : null,
          decoration: InputDecoration(hintText: l.portalEmailPh, labelText: l.portalEmailPh),
        ),
        if (state.error != null) ...[
          const SizedBox(height: 12),
          Text(localizedApiMessage(l, state.error!), style: t.bodySmall?.copyWith(color: context.tokens.dangerInk)),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: FilledButton(
            // Disabled until the address contains '@', exactly as the prototype gates it.
            onPressed: state.canContinue && !state.busy ? ctrl.requestCode : null,
            child: state.busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.portalContinue),
          ),
        ),
        const SizedBox(height: 10),
        // The prototype has no "report a death" link in the landing footer, so the
        // entry to the claim flow lives here, on the screen a bereaved family
        // member actually arrives at.
        Center(
          child: TextButton(
            onPressed: () => context.go('/claim'),
            style: TextButton.styleFrom(foregroundColor: context.tokens.faint),
            child: Text(l.portalReportDeath),
          ),
        ),
      ],
    );
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      child: SizedBox(
        height: 48, // >= 44px (spec §7)
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            backgroundColor: selected ? tokens.gold.withValues(alpha: 0.12) : Colors.transparent,
            foregroundColor: selected ? tokens.goldInk : tokens.muted,
            side: BorderSide(color: selected ? tokens.gold : tokens.hairline, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// --- Step 2: the code --------------------------------------------------------

class _CodeStep extends ConsumerStatefulWidget {
  const _CodeStep({required this.controller, required this.focusNode});
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  ConsumerState<_CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends ConsumerState<_CodeStep> {
  Future<void> _verify() async {
    if (widget.controller.text.length < 6) return;
    final ok = await ref.read(portalControllerProvider.notifier).verifyCode(widget.controller.text.trim());
    // TextField.onChanged does NOT fire for a programmatic controller mutation, and
    // CodeCells paints straight from controller.text, so the clear must schedule its
    // own rebuild. Without this the six cells keep showing the rejected digits, and
    // only happen to repaint today because verifyCode also sets an error.
    if (!ok && mounted) setState(widget.controller.clear);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final state = ref.watch(portalControllerProvider);
    final ctrl = ref.read(portalControllerProvider.notifier);

    return AuthScaffold(
      title: l.portalCodeTitle,
      // DEVIATION FROM THE PROTOTYPE, deliberate: portalCodeSub hardcodes "sent to
      // your registered mobile", but WillHeirContact.phone is optional and the
      // backend sends to the roster's email when there is no phone. The heir who
      // gets it by email would otherwise be told to check a phone that was never
      // asked for. We cannot know which channel was used (the API does not say, and
      // saying would leak which contact details are on file), so the email variant
      // is shown when the party signed in with an address — which is always, since
      // the sign-in field IS an email.
      subtitle: l.portalCodeSubEmail,
      centered: true,
      showSeal: false,
      onBack: ctrl.exit,
      children: [
        CodeCells(
          controller: widget.controller,
          focusNode: widget.focusNode,
          onCompleted: _verify,
          onChanged: () => setState(() {}),
          semanticLabel: l.portalCodeTitle,
        ),
        if (state.error != null) ...[
          const SizedBox(height: 14),
          Text(localizedApiMessage(l, state.error!),
              textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: context.tokens.dangerInk)),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: widget.controller.text.length == 6 && !state.busy ? _verify : null,
            child: state.busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.portalContinue),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ResendCountdown(
            builder: (context, left, restart) => left > 0
                // A duration IS a computed number, so it is localised. The CODE
                // itself never is — see CodeCells.
                ? Text(context.digits(l.portalCodeResendWait(left)),
                    style: t.bodySmall?.copyWith(color: context.tokens.muted))
                : Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${l.portalCodeResendReady} ',
                        style: t.bodySmall?.copyWith(color: context.tokens.muted)),
                    TextButton(
                      onPressed: () {
                        ctrl.resendCode();
                        restart();
                      },
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 0)),
                      child: Text(l.portalCodeResend),
                    ),
                  ]),
          ),
        ),
      ],
    );
  }
}

// --- Step 3: the read-only view ---------------------------------------------

class _PortalView extends ConsumerWidget {
  const _PortalView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final state = ref.watch(portalControllerProvider);
    final ctrl = ref.read(portalControllerProvider.notifier);
    final status = state.claim?.status ?? state.me?.claimStatus;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Header: estate, role chip, READ-ONLY chip, Exit portal.
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(state.me?.estateName ?? '', style: t.headlineSmall),
                    ),
                    _Chip(
                      label: state.me?.role == PortalRole.trustee ? l.portalChipTrustee : l.portalChipHeir,
                      color: tokens.goldInk,
                      border: tokens.gold,
                    ),
                    _Chip(
                      label: l.portalReadOnly,
                      color: WasiatiColors.onDark,
                      background: WasiatiColors.inkNavy,
                    ),
                    SizedBox(
                      height: 44,
                      child: TextButton(
                        onPressed: () async {
                          await ctrl.exit();
                          if (context.mounted) context.go('/portal');
                        },
                        style: TextButton.styleFrom(foregroundColor: tokens.faint),
                        child: Text(l.portalSignOut),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (state.error != null) ...[
                  Text(localizedApiMessage(l, state.error!), style: t.bodySmall?.copyWith(color: tokens.dangerInk)),
                  const SizedBox(height: 12),
                ],

                // Before anything else: a trustee who never accepted the role sees only
                // this. The estate is closed to them until they answer the appointment, and
                // showing the roll-call or an empty released view first would leave them
                // hunting for why nothing loads.
                if (state.me?.trusteeAcceptancePending == true)
                  const _AcceptTrusteeshipCard()
                else if (status == ClaimStatus.released)
                  const _ReleasedView()
                else if (status == ClaimStatus.approved)
                  const _ApprovedView()
                else if (status == ClaimStatus.rejected)
                  _NoticeCard(
                    icon: Icons.info_outline,
                    iconColor: tokens.muted,
                    title: l.portalRejectedTitle,
                    body: l.portalRejectedSub,
                  )
                else
                  _NoticeCard(
                    icon: Icons.hourglass_empty,
                    iconColor: tokens.goldInk,
                    title: l.portalPendingTitle,
                    body: l.portalPendingSub,
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The prototype's pending card — centred glyph, title, supporting line.
///
/// The prototype paints its glyph as a pasted ⏳ emoji. That is a bundled-font
/// tofu risk (CLAUDE.md: "No pasted symbol glyphs … two commits already purged
/// these"), so it is drawn as a Material icon instead — the same substitution
/// pricing_screen.dart:495 and review_seal_screen.dart:211 already make.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.hairline),
      ),
      child: Column(children: [
        // Decorative — a screen reader reads the title, not the glyph.
        ExcludeSemantics(child: Icon(icon, size: 26, color: iconColor)),
        const SizedBox(height: 8),
        Text(title, textAlign: TextAlign.center, style: t.titleLarge),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(body,
              textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: tokens.muted, height: 1.6)),
        ),
      ]),
    );
  }
}

/// The trustee was named on this will but never accepted the role.
///
/// Being named is the testator's half of the appointment; accepting is theirs, and until
/// they give it the estate stays closed and the heirs cannot be overridden. The invitation
/// link that used to be the only way to accept was mailed when the will was written — often
/// years earlier — so this is where the answer is actually given.
class _AcceptTrusteeshipCard extends ConsumerWidget {
  const _AcceptTrusteeshipCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final state = ref.watch(portalControllerProvider);
    final ctrl = ref.read(portalControllerProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.hairline),
      ),
      child: Column(children: [
        ExcludeSemantics(child: Icon(Icons.handshake_outlined, size: 26, color: tokens.goldInk)),
        const SizedBox(height: 8),
        Text(l.portalAcceptTrusteeTitle, textAlign: TextAlign.center, style: t.titleLarge),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Text(
            l.portalAcceptTrusteeBody,
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: tokens.muted, height: 1.6),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: state.busy ? null : ctrl.acceptTrusteeship,
          child: state.busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.portalAcceptTrusteeBtn, textAlign: TextAlign.center),
        ),
      ]),
    );
  }
}

/// APPROVED — the heir roll-call, plus this session's one action.
class _ApprovedView extends ConsumerWidget {
  const _ApprovedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final state = ref.watch(portalControllerProvider);
    final ctrl = ref.read(portalControllerProvider.notifier);
    final claim = state.claim;
    final isHeir = state.me?.role == PortalRole.heir;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.gold),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.portalApprovedTitle, style: t.titleLarge),
        const SizedBox(height: 3),
        Text(l.portalApprovedSub, style: t.bodySmall?.copyWith(color: tokens.muted, height: 1.6)),
        const SizedBox(height: 14),
        Text(
          l.heirApprovalsTitle,
          style: t.labelSmall?.copyWith(color: tokens.muted, letterSpacing: 0.6, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        // Only the heirs the release actually waits on. `reachable` mirrors the
        // backend gate (!isMinor && (phone || email)); listing an unreachable heir
        // as "awaiting" would show a family a confirmation that is never coming.
        ...?claim?.awaited.map((h) => _RollCallRow(heir: h)),
        if (isHeir) ...[
          const SizedBox(height: 14),
          if (claim?.myConfirmationPending ?? false)
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: state.busy ? null : ctrl.confirmRelease,
                style: FilledButton.styleFrom(backgroundColor: tokens.goldInk, foregroundColor: WasiatiColors.onDark),
                child: state.busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.heirConfirmBtn),
              ),
            )
          else
            _ConfirmedNote(text: l.heirConfirmedNote),
          const SizedBox(height: 8),
          Text(l.portalWaitOthers, style: t.bodySmall?.copyWith(color: tokens.faint, height: 1.5)),
        ],
        if (!isHeir) ...[
          const SizedBox(height: 14),
          if (claim?.overrideActive ?? false)
            _ConfirmedNote(text: l.overrideOnNote)
          else
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: state.busy ? null : ctrl.overrideRelease,
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.dangerInk,
                  side: BorderSide(color: tokens.dangerInk, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: state.busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.trusteeOverrideBtn, textAlign: TextAlign.center),
              ),
            ),
        ],
      ]),
    );
  }
}

/// A recorded-and-done line. The tick is a Material icon, never a pasted ✓ —
/// that character is tofu in the bundled fonts and this is the screen where a
/// missing glyph would be least forgivable.
class _ConfirmedNote extends StatelessWidget {
  const _ConfirmedNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Decorative: the sentence beside it already carries the meaning.
      ExcludeSemantics(child: Icon(Icons.check, size: 16, color: tokens.successInk)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: tokens.successInk, fontWeight: FontWeight.w600),
        ),
      ),
    ]);
  }
}

class _RollCallRow extends StatelessWidget {
  const _RollCallRow({required this.heir});
  final HeirConfirmation heir;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final tokens = context.tokens;
    // Material icons, not the prototype's pasted ✓ / · — see _ConfirmedNote.
    final markColor = heir.confirmed ? tokens.successInk : tokens.faint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tokens.hairline))),
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(children: [
          // The glyph is decoration; the state is spoken via the trailing label.
          ExcludeSemantics(
            child: Icon(
              heir.confirmed ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: markColor,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text('${heir.name} · ${heirRelLabel(l, heir.relation)}',
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Text(heir.confirmed ? l.portalConfirmedMark : l.portalAwaitingMark,
              style: t.bodySmall?.copyWith(color: markColor)),
        ]),
      ),
    );
  }
}

/// RELEASED — the heir view, transcribed from the prototype (:1943-1994).
///
/// TWO DELIBERATE OMISSIONS from that transcription, both of which the prototype has
/// and this does not:
///
///  1. `heirVaultNote` ("Vault items assigned to you are available in your Wasiati
///     account"). Vault items are end-to-end encrypted under a passphrase the server
///     never holds — the product tells the owner "not even by us" can it be
///     recovered — so heirs do NOT receive them this way. Printing that line on the
///     most emotionally loaded screen in the app would be a promise no code here can
///     keep. Only the debts sentence from that paragraph survives, which is true.
///  2. The `DECRYPTED FOR YOU` chip on the video. Legacy videos are ordinary S3
///     objects with at-rest encryption, not end-to-end, and the chip implies a
///     guarantee that is not being made.
class _ReleasedView extends ConsumerWidget {
  const _ReleasedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final state = ref.watch(portalControllerProvider);
    final will = state.will;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 10),
      const Center(child: Seal(size: 72, status: SealStatus.sealed)),
      const SizedBox(height: 14),
      // Qur'an 2:156 — Qur'anic text, so it renders in Amiri (the classical serif),
      // not the Arabic UI face. Identical in both locales; it is not translated.
      Center(
        child: Text(
          l.portalIstirjaa,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
          style: WasiatiType.arabicSerif(
            TextStyle(fontSize: 20, color: tokens.goldInk, height: 1.8),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(l.heirTitle(state.me?.estateName ?? ''), textAlign: TextAlign.center, style: t.headlineMedium),
      const SizedBox(height: 8),
      Text(l.heirSub,
          textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: tokens.muted, height: 1.6)),
      const SizedBox(height: 18),

      // WORDS FOR MY FAMILY
      _SectionCard(
        title: l.wordsTitle,
        titleColor: tokens.goldInk,
        borderColor: tokens.gold,
        child: Text(
          (will?.personalMessage?.trim().isNotEmpty ?? false) ? '“${will!.personalMessage!}”' : l.heirNoWords,
          style: t.bodyMedium?.copyWith(
            height: 1.7,
            fontStyle: (will?.personalMessage?.trim().isNotEmpty ?? false) ? FontStyle.italic : FontStyle.normal,
            color: (will?.personalMessage?.trim().isNotEmpty ?? false) ? null : tokens.muted,
          ),
        ),
      ),

      // Oldest first, exactly as the endpoint orders them — the order they were
      // recorded is the order the family should watch them.
      for (final video in state.videos) ...[
        const SizedBox(height: 12),
        _VideoCard(video: video),
      ],

      // DIVISION OF THE ESTATE
      const SizedBox(height: 12),
      _SectionCard(
        title: l.heirSharesTitle,
        titleColor: tokens.muted,
        borderColor: tokens.hairline,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ...?will?.shariaShares.map((s) => _ShareRow(
                name: s.heirName,
                detail: heirRelLabel(l, s.heirRelation),
                percent: s.sharePercent,
              )),
          const SizedBox(height: 8),
          // The only sentence kept from the prototype's heirVaultNote paragraph.
          Text(l.portalDebtsNote, style: t.bodySmall?.copyWith(color: tokens.faint, height: 1.5)),
        ]),
      ),

      if (will?.bequests.isNotEmpty ?? false) ...[
        const SizedBox(height: 12),
        _SectionCard(
          title: l.heirBequestsTitle,
          titleColor: tokens.muted,
          borderColor: tokens.hairline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: will!.bequests
                .map((b) => _ShareRow(name: b.beneficiaryName, detail: b.notes ?? '', percent: b.sharePercent))
                .toList(),
          ),
        ),
      ],

      // THE INVENTORY — what the family has to be able to find.
      //
      // The server has always sent this, complete and with accountRef unmasked, and the
      // parser threw it away. So a testator who recorded six accounts with their IBANs and
      // branch numbers handed his heirs a personal message and a list of percentages, and
      // the 90-day purge then erased the references for good. The PDF was no fallback: its
      // renderer only ever receives type/label/institution/value/currency.
      if (will?.assets.isNotEmpty ?? false) ...[
        const SizedBox(height: 12),
        _SectionCard(
          title: l.wdocEstateTitle,
          titleColor: tokens.muted,
          borderColor: tokens.hairline,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final a in will!.assets) _AssetRow(asset: a),
            const SizedBox(height: 4),
            Text(l.portalInventoryNote, style: t.bodySmall?.copyWith(color: tokens.faint, height: 1.5)),
          ]),
        ),
      ],

      // FUNERAL & BURIAL WISHES — reusing the exact strings the will document renders,
      // so the family reads the same sentences in both places.
      if (_wishLines(l, will?.funeralWishes).isNotEmpty) ...[
        const SizedBox(height: 12),
        _SectionCard(
          title: l.wdocWishesTitle,
          titleColor: tokens.muted,
          borderColor: tokens.hairline,
          child: Text(_wishLines(l, will!.funeralWishes).join(' · '),
              style: t.bodyMedium?.copyWith(height: 1.7)),
        ),
      ],

      // GUARDIANSHIP OF MINOR CHILDREN — the single most time-critical thing in a will,
      // and it was reaching nobody.
      if (will?.guardianship != null) ...[
        const SizedBox(height: 12),
        _SectionCard(
          title: l.cwGuardTitle,
          titleColor: tokens.muted,
          borderColor: tokens.hairline,
          child: _GuardianBody(guardianship: will!.guardianship!),
        ),
      ],

      // The executed will itself. Last, because everything above is what the family
      // reads here and now; this is the document they keep.
      const SizedBox(height: 12),
      const _WillPdfCard(),
    ]);
  }
}

/// The wishes the testator ticked, in the will document's own words.
List<String> _wishLines(AppLocalizations l, Map<String, dynamic>? wishes) {
  if (wishes == null) return const [];
  bool on(String k) => wishes[k] == true;
  return [
    if (on('sunnah')) l.cwWish1,
    if (on('simple')) l.cwWish2,
    if (on('local')) l.cwWish3,
    on('azaa') ? l.cwWish4 : l.cwWish4No,
  ];
}

/// One inventory line, with everything the family needs to reach the institution.
class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.asset});
  final PortalAsset asset;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final isLiability = assetKindFromType(asset.type) == 'LIABILITY';

    // label · institution on one line; the reference and contacts beneath it. Everything
    // is optional on the roster, so each line only appears when it was actually recorded.
    final details = <String>[
      if ((asset.accountRef ?? '').trim().isNotEmpty) '${l.portalAssetRef}: ${asset.accountRef}',
      if ((asset.contactPhone ?? '').trim().isNotEmpty) '${l.assetColPhone}: ${asset.contactPhone}',
      if ((asset.contactEmail ?? '').trim().isNotEmpty) '${l.assetColEmail}: ${asset.contactEmail}',
      if ((asset.notes ?? '').trim().isNotEmpty) asset.notes!.trim(),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(
              [asset.label, if ((asset.institution ?? '').trim().isNotEmpty) asset.institution!].join(' · '),
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (asset.estimatedValue != null) ...[
            const SizedBox(width: 10),
            Text(
              '${isLiability ? '−' : ''}${asset.estimatedValue!.toStringAsFixed(0)} ${asset.currency ?? ''}'.trim(),
              style: t.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isLiability ? tokens.dangerInk : null,
              ),
            ),
          ],
        ]),
        for (final d in details) ...[
          const SizedBox(height: 2),
          // SelectableText, deliberately: an IBAN is meant to be copied into a bank's form,
          // and re-typing a 23-character reference by hand is how a digit gets lost.
          SelectableText(d, style: t.bodySmall?.copyWith(color: tokens.muted, height: 1.5)),
        ],
      ]),
    );
  }
}

/// Who cares for the children, and how to reach them.
class _GuardianBody extends StatelessWidget {
  const _GuardianBody({required this.guardianship});
  final PortalGuardianship guardianship;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final mode = switch (guardianship.mode) {
      'PARENT' => l.cwGParentNote,
      'ISLAMIC' => l.cwGIslamicLbl,
      _ => guardianship.name ?? l.cwGNamedLbl,
    };
    final contacts = <String>[
      if ((guardianship.phone ?? '').trim().isNotEmpty) guardianship.phone!,
      if ((guardianship.email ?? '').trim().isNotEmpty) guardianship.email!,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(mode, style: t.bodyMedium?.copyWith(height: 1.6)),
      if (contacts.isNotEmpty) ...[
        const SizedBox(height: 4),
        SelectableText(contacts.join(' · '),
            style: t.bodySmall?.copyWith(color: tokens.muted, height: 1.5)),
      ],
    ]);
  }
}

/// Downloads the executed will as a PDF.
///
/// GET /portal/will/pdf shipped server-side without a client, so until now this was the
/// one artifact heirs exist to receive and the only one they could not get. It downloads
/// rather than rendering inline: a family may need to hand it to a court or a bank.
class _WillPdfCard extends ConsumerStatefulWidget {
  const _WillPdfCard();
  @override
  ConsumerState<_WillPdfCard> createState() => _WillPdfCardState();
}

class _WillPdfCardState extends ConsumerState<_WillPdfCard> {
  bool _busy = false;

  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    // In-memory on the controller state — never persisted, never in the URL.
    final token = ref.read(portalControllerProvider).token;
    if (token == null) return;
    // Follow the reader's own language: an Arabic-speaking family should not be handed
    // an English document by default. Captured BEFORE the await, along with the fallback
    // message — the widget can be gone by the time the download resolves.
    final lang = context.isRtl ? 'ar' : 'en';
    final genericError = context.l10n.authGenericError;
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(portalApiProvider).pdf(token, lang: lang);
      await Printing.sharePdf(bytes: bytes, filename: 'wasiati-will-$lang.pdf');
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      // Not just ApiException: the share/print step can fail on its own (no handler for
      // the file type, a dismissed browser dialog). Swallowing that would leave the
      // button spinning with nothing said, on the one screen where a stuck control is
      // least forgivable. Mirrors shareWillPdf on the owner side.
      messenger.showSnackBar(SnackBar(content: Text(genericError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    return _SectionCard(
      title: l.portalWillPdfTitle,
      titleColor: context.tokens.muted,
      borderColor: context.tokens.hairline,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.portalWillPdfSub, style: t.bodySmall?.copyWith(color: context.tokens.muted, height: 1.5)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _download,
          icon: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const WasiatiIcon(svg: WasiatiIcons.download, size: 18),
          label: Text(l.portalWillPdfDownload),
        ),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.titleColor,
    required this.borderColor,
    required this.child,
  });
  final String title;
  final Color titleColor;
  final Color borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: context.tokens.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: t.labelSmall?.copyWith(color: titleColor, letterSpacing: 0.6, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.name, required this.detail, required this.percent});
  final String name;
  final String detail;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tokens = context.tokens;
    // A computed quantity, so it reads in the locale's own digits — Arabic-Indic
    // under `ar`, beside the Arabic-Indic literals in the rest of the copy.
    final pct = context.digits('${_trim(percent)}%');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tokens.hairline))),
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (detail.isNotEmpty)
                Text(detail, style: t.bodySmall?.copyWith(color: tokens.muted)),
            ]),
          ),
          const SizedBox(width: 10),
          Text(pct, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  /// 25.0 → "25", 12.5 → "12.5".
  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
}

class _VideoCard extends ConsumerStatefulWidget {
  const _VideoCard({required this.video});
  final PortalVideo video;

  @override
  ConsumerState<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends ConsumerState<_VideoCard> {
  bool _opening = false;

  PortalVideo get video => widget.video;

  /// Fetches a URL at the moment of the tap rather than using the one from sign-in.
  ///
  /// The signed URL lives five minutes and the list was fetched once per session, so any
  /// tap more than five minutes after signing in opened S3's raw AccessDenied XML — and
  /// silently, because an expired presigned URL is still a well-formed https URL, so the
  /// launch "succeeded" and no error was ever shown.
  Future<void> _open() async {
    if (_opening) return;
    final messenger = ScaffoldMessenger.of(context);
    final errorText = context.l10n.portalLoadError;
    setState(() => _opening = true);
    try {
      final url = await ref.read(portalControllerProvider.notifier).freshVideoUrl(video.fileId);
      if (url == null) {
        messenger.showSnackBar(SnackBar(content: Text(errorText)));
        return;
      }
      if (!await safeLaunchExternal(url)) {
        messenger.showSnackBar(SnackBar(content: Text(errorText)));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    // l10n.localeName, matching wills_list_screen.dart:209 and
    // admin_console_screen.dart:11. NOTE: nothing in the app calls
    // initializeDateFormatting(), so non-en locale data is not loaded and intl
    // falls back rather than being guaranteed correct here. That gap is
    // app-wide and pre-existing, not specific to this screen — but it is worth
    // closing before launch, because this is the one screen where a formatting
    // failure would land on a grieving family.
    final date =
        video.recordedAt == null ? '' : DateFormat.yMMMMd(l.localeName).format(video.recordedAt!);

    return Semantics(
      button: true,
      label: l.heirVideoOpen,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _opening ? null : _open,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(color: WasiatiColors.inkNavy, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: WasiatiColors.brassGold, shape: BoxShape.circle),
              child: _opening
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2, color: WasiatiColors.inkNavy),
                    )
                  : const Icon(Icons.play_arrow_rounded, color: WasiatiColors.inkNavy),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.heirVideoTitle,
                    style: t.titleSmall?.copyWith(color: WasiatiColors.onDark, fontWeight: FontWeight.w700)),
                if (date.isNotEmpty)
                  // A date is a computed number too.
                  Text(context.digits(l.heirVideoMeta(date)),
                      style: t.bodySmall?.copyWith(color: WasiatiColors.onDark.withValues(alpha: 0.72))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.background, this.border});
  final String label;
  final Color color;
  final Color? background;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(99),
          border: border == null ? null : Border.all(color: border!, width: 1.5),
        ),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w700, letterSpacing: 0.6, fontSize: 10),
        ),
      );
}
