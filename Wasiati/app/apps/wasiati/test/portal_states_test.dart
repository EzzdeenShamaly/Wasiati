import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/features/portal/application/portal_providers.dart';
import 'package:wasiati/features/portal/domain/portal_models.dart';
import 'package:wasiati/features/portal/presentation/portal_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// The portal's three read-only states, and the one rule that cannot be got wrong
/// on the released screen: it must not promise heirs the vault.
///
/// Vault items are end-to-end encrypted under a passphrase the server never holds.
/// The prototype's `heirVaultNote` says they "are available in your Wasiati
/// account", which the product cannot deliver — and this is the screen a family
/// reads on the worst day of their lives. The omission is pinned here so a future
/// "finish transcribing the prototype" pass cannot quietly restore it.

/// Holds a fixed PortalState. Overriding build() keeps the controller from doing
/// any network work.
class _FixedPortal extends PortalController {
  _FixedPortal(this._state);
  final PortalState _state;

  @override
  PortalState build() => _state;
}

Future<void> _pump(WidgetTester t, PortalState state, {Locale locale = const Locale('en')}) async {
  t.view.physicalSize = const Size(700, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: [portalControllerProvider.overrideWith(() => _FixedPortal(state))],
    child: MaterialApp(
      locale: locale,
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const PortalScreen(),
    ),
  ));
  await t.pumpAndSettle();
}

const _me = PortalMe(role: PortalRole.heir, estateName: 'ahmed@example.com', claimStatus: null);
const _trusteeMe = PortalMe(role: PortalRole.trustee, estateName: 'ahmed@example.com', claimStatus: null);

PortalState _viewing(PortalClaim claim, {PortalMe me = _me, PortalWill? will}) => PortalState(
      step: PortalStep.view,
      token: 'tok',
      me: me,
      claim: claim,
      will: will,
    );

/// Every visible string on screen, in one bag.
Iterable<String> _texts(WidgetTester t) =>
    t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').where((s) => s.isNotEmpty);

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  group('step 1 — role + email', () {
    testWidgets('renders the role segment and gates Continue on an @', (t) async {
      await _pump(t, const PortalState());
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.text(l.portalRoleHeir), findsOneWidget);
      expect(find.text(l.portalRoleTrustee), findsOneWidget);

      final button = t.widget<FilledButton>(
        find.ancestor(of: find.text(l.portalContinue), matching: find.byType(FilledButton)),
      );
      expect(button.onPressed, isNull,
          reason: 'The prototype disables Continue until the address contains an @.');
    });

    testWidgets('?role=trustee preselects the trustee segment, and grants nothing', (t) async {
      t.view.physicalSize = const Size(700, 1800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: WasiatiTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PortalScreen(roleParam: 'trustee'),
        ),
      ));
      await t.pumpAndSettle();

      final state = container.read(portalControllerProvider);
      expect(state.role, PortalRole.trustee);
      // The prefill is cosmetic. It must NOT skip the code step or mint a session.
      expect(state.step, PortalStep.signIn,
          reason: 'The role in the deep link grants nothing — the recipient still does email → code.');
      expect(state.token, isNull);
    });
  });

  group('step 3 — the three read-only states', () {
    testWidgets('PENDING renders "Claim under review"', (t) async {
      await _pump(t, _viewing(const PortalClaim(status: ClaimStatus.submitted)));
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.text(l.portalPendingTitle), findsOneWidget);
      expect(find.text(l.portalReadOnly), findsOneWidget);
      expect(find.text(l.portalSignOut), findsOneWidget);
      // Below APPROVED the backend sends only { status } — nothing may be invented.
      expect(find.text(l.heirApprovalsTitle), findsNothing);
    });

    testWidgets('APPROVED renders the roll-call and the heir confirm button', (t) async {
      await _pump(
        t,
        _viewing(const PortalClaim(
          status: ClaimStatus.approved,
          myConfirmationPending: true,
          heirConfirmations: [
            HeirConfirmation(
              heirContactId: 'h1',
              name: 'Yusuf',
              relation: 'SON',
              reachable: true,
              confirmed: true,
              confirmedAt: null,
            ),
            HeirConfirmation(
              heirContactId: 'h2',
              name: 'Maryam',
              relation: 'DAUGHTER',
              reachable: true,
              confirmed: false,
              confirmedAt: null,
            ),
            // A minor: unreachable, so the release gate does not wait on them and
            // the roll-call must not list them as outstanding.
            HeirConfirmation(
              heirContactId: 'h3',
              name: 'Salma',
              relation: 'DAUGHTER',
              reachable: false,
              confirmed: false,
              confirmedAt: null,
            ),
          ],
        )),
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.text(l.portalApprovedTitle), findsOneWidget);
      expect(find.text(l.heirApprovalsTitle), findsOneWidget);
      expect(find.textContaining('Yusuf'), findsOneWidget);
      expect(find.textContaining('Maryam'), findsOneWidget);
      expect(find.textContaining('Salma'), findsNothing,
          reason: 'reachable:false mirrors the backend gate. Listing an unreachable heir '
              'as "awaiting" shows a family a confirmation that is never coming.');
      expect(find.text(l.heirConfirmBtn), findsOneWidget);
      // A heir must never see the trustee's override.
      expect(find.text(l.trusteeOverrideBtn), findsNothing);
    });

    testWidgets('APPROVED shows the trustee the override, not the heir button', (t) async {
      await _pump(
        t,
        _viewing(
          const PortalClaim(status: ClaimStatus.approved, heirConfirmations: []),
          me: _trusteeMe,
        ),
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.text(l.trusteeOverrideBtn), findsOneWidget);
      expect(find.text(l.heirConfirmBtn), findsNothing);
      expect(find.text(l.portalChipTrustee), findsOneWidget);
    });

    testWidgets('RELEASED renders the words, the estate division and the istirjāʿ line', (t) async {
      await _pump(
        t,
        _viewing(
          const PortalClaim(status: ClaimStatus.released),
          will: const PortalWill(
            estateName: 'ahmed@example.com',
            personalMessage: 'Look after your mother.',
            shariaShares: [
              ShariaShare(heirName: 'Yusuf', heirRelation: 'SON', sharePercent: 50),
              ShariaShare(heirName: 'Maryam', heirRelation: 'DAUGHTER', sharePercent: 25),
            ],
            bequests: [],
          ),
        ),
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.text(l.wordsTitle), findsOneWidget);
      expect(find.text(l.heirSharesTitle), findsOneWidget);
      expect(find.textContaining('Look after your mother.'), findsOneWidget);
      expect(find.text(l.portalIstirjaa), findsOneWidget);
    });
  });

  group('the vault promise is NOT made', () {
    testWidgets('the released view says nothing about vault items reaching heirs', (t) async {
      await _pump(
        t,
        _viewing(
          const PortalClaim(status: ClaimStatus.released),
          will: const PortalWill(
            estateName: 'ahmed@example.com',
            personalMessage: 'Look after your mother.',
            shariaShares: [ShariaShare(heirName: 'Yusuf', heirRelation: 'SON', sharePercent: 100)],
            bequests: [],
          ),
        ),
      );

      final all = _texts(t).join(' | ').toLowerCase();
      expect(all.contains('vault'), isFalse,
          reason: 'Vault items are E2E-encrypted under a passphrase the server never holds. '
              'The prototype\'s heirVaultNote promises heirs something the product cannot '
              'deliver, and this is the most emotionally loaded screen in the app.');
      expect(all.contains('decrypted'), isFalse,
          reason: 'Legacy videos are ordinary S3 objects with at-rest encryption, not E2E. '
              'The DECRYPTED FOR YOU chip implies a guarantee that is not being made.');
      // The one sentence from that paragraph that IS true survives.
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l.portalDebtsNote), findsOneWidget);
    });
  });

  group('no pasted symbol glyphs', () {
    testWidgets('the tofu-prone characters never reach the tree', (t) async {
      // CLAUDE.md: "No pasted symbol glyphs. Characters like ✦ ⅛ ⅓ › ✓ from the web
      // prototype render as tofu (□) in the bundled fonts — use Icons.*, drawn
      // widgets, or localized text (two commits already purged these; don't
      // reintroduce them)." The prototype paints the roll-call tick, the override
      // note and the pending card as pasted ✓ and ⏳; all three are Material icons
      // here, and this pins that so a "finish the transcription" pass cannot undo it.
      for (final state in [
        _viewing(const PortalClaim(status: ClaimStatus.submitted)),
        _viewing(const PortalClaim(
          status: ClaimStatus.approved,
          heirConfirmations: [
            HeirConfirmation(
              heirContactId: 'h1',
              name: 'Yusuf',
              relation: 'SON',
              reachable: true,
              confirmed: true,
              confirmedAt: null,
            ),
          ],
        )),
        _viewing(const PortalClaim(status: ClaimStatus.approved, overrideActive: true), me: _trusteeMe),
      ]) {
        await _pump(t, state);
        final shown = _texts(t).join();
        for (final glyph in ['✓', '✦', '⅛', '⅓', '›', '⏳', '✕']) {
          expect(shown.contains(glyph), isFalse,
              reason: '"$glyph" renders as □ in the bundled fonts. Use Icons.* instead.');
        }
      }
    });
  });

  group('an expired session does not strand the reader', () {
    testWidgets('a 401 drops back to sign-in, keeping the role and address', (t) async {
      // A live session, seeded as the controller's build state: PORTAL_TOKEN_TTL_HOURS
      // defaults to 12, so a tab left open overnight is the ordinary case, not an edge one.
      final container = ProviderContainer(overrides: [
        portalControllerProvider.overrideWith(
          () => _FixedPortal(const PortalState(
            step: PortalStep.view,
            role: PortalRole.trustee,
            email: 'fatima@example.com',
            token: 'dead-token',
            me: _trusteeMe,
            claim: PortalClaim(status: ClaimStatus.approved),
          )),
        ),
      ]);
      addTearDown(container.dispose);

      container
          .read(portalControllerProvider.notifier)
          .sessionExpired('This link has expired or has already been used.');

      final after = container.read(portalControllerProvider);
      expect(after.step, PortalStep.signIn,
          reason: 'Leaving them on the read-only screen shows stale data behind an error '
              'line while every further tap fails the same way.');
      expect(after.token, isNull);
      expect(after.claim, isNull);
      expect(after.role, PortalRole.trustee, reason: 'The way back in should be one tap, not a blank form.');
      expect(after.email, 'fatima@example.com');
      expect(after.error, isNotNull);
    });
  });

  group('accessibility & RTL', () {
    testWidgets('shares render in Arabic-Indic digits under ar', (t) async {
      await _pump(
        t,
        _viewing(
          const PortalClaim(status: ClaimStatus.released),
          will: const PortalWill(
            estateName: 'ahmed@example.com',
            personalMessage: null,
            shariaShares: [
              ShariaShare(heirName: 'يوسف', heirRelation: 'SON', sharePercent: 50),
              ShariaShare(heirName: 'مريم', heirRelation: 'DAUGHTER', sharePercent: 25),
            ],
            bequests: [],
          ),
        ),
        locale: const Locale('ar'),
      );

      expect(find.text('٥٠%'), findsOneWidget,
          reason: 'A share is a COMPUTED number, so it must go through context.digits() — '
              'intl\'s ar NumberFormat does not yield Arabic-Indic on its own.');
      expect(find.text('٢٥%'), findsOneWidget);
      // Not a single Western digit anywhere on the screen.
      final western = RegExp(r'[0-9]');
      final offenders = _texts(t).where(western.hasMatch).toList();
      expect(offenders, isEmpty, reason: 'Unlocalised digits leaked: $offenders');
    });

    testWidgets('the whole released view mirrors to RTL under ar', (t) async {
      await _pump(
        t,
        _viewing(
          const PortalClaim(status: ClaimStatus.released),
          will: const PortalWill(
            estateName: 'a@b.com',
            personalMessage: null,
            shariaShares: [],
            bequests: [],
          ),
        ),
        locale: const Locale('ar'),
      );

      expect(Directionality.of(t.element(find.byType(PortalScreen))), TextDirection.rtl);
    });

    testWidgets('every tappable control clears the 44px minimum', (t) async {
      await _pump(
        t,
        _viewing(const PortalClaim(status: ClaimStatus.approved, myConfirmationPending: true)),
      );

      for (final type in [find.byType(FilledButton), find.byType(OutlinedButton)]) {
        for (final e in t.widgetList(type)) {
          final size = t.getSize(find.byWidget(e));
          expect(size.height, greaterThanOrEqualTo(44.0),
              reason: 'spec §7: a brand-new public flow is exactly where touch targets get forgotten.');
        }
      }
    });
  });
}
