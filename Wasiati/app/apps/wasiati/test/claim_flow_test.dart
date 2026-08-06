import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/features/death_claims/application/claim_providers.dart';
import 'package:wasiati/features/death_claims/presentation/claim_lookup_screen.dart';
import 'package:wasiati/features/death_claims/presentation/claim_submit_screen.dart';
import 'package:wasiati/features/files/domain/file_models.dart';
import 'package:wasiati/l10n/app_localizations.dart';

/// The claim flow's two non-negotiables.
///
/// 1. THE CERTIFICATE IS REQUIRED. The backend refuses a submit whose file is not
///    kind 'death_certificate' with scanStatus CLEAN, so a submit button that is
///    live without one only produces a 400 a grieving claimant cannot act on.
/// 2. THE LOOKUP NEVER CONFIRMS OR DENIES. The endpoint answers 202
///    { acknowledged: true } identically for an unknown person, a person with no
///    sealed will, a claimant who is not a party, and a full match — that
///    uniformity is the entire reason the endpoint exists, and the screen must not
///    undo it by phrasing success as "we found them".

class _FixedSubmit extends ClaimSubmitController {
  _FixedSubmit(this._state);
  final ClaimSubmitState _state;

  @override
  ClaimSubmitState build() => _state;

  /// The screen kicks off a link check on mount. This fake exists to pin how ONE state
  /// renders, so the check must not run and move the state somewhere else — in a widget
  /// test there is no server, and the real one would fall through to the form.
  @override
  Future<void> checkLink(String claimToken) async {}
}

class _FixedLookup extends ClaimLookupController {
  _FixedLookup(this._state);
  final ClaimLookupState _state;

  @override
  ClaimLookupState build() => _state;
}

/// [settle] is false for the link-checking state: a CircularProgressIndicator animates
/// forever, so pumpAndSettle can never return while one is on screen.
Future<void> _pump(WidgetTester t, Widget home, List<Override> overrides, {bool settle = true}) async {
  t.view.physicalSize = const Size(700, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  ));
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
  }
}

const _cert = StoredFile(
  id: '11111111-2222-3333-4444-555555555555',
  kind: 'death_certificate',
  key: 'death-certificates/owner/abc.pdf',
  contentType: 'application/pdf',
  sizeBytes: 1024,
);

FilledButton _submitButton(WidgetTester t, AppLocalizations l) => t.widget<FilledButton>(
      find.ancestor(of: find.text(l.pcSubmitBtn), matching: find.byType(FilledButton)),
    );

void main() {
  group('the death certificate is REQUIRED before submit', () {
    testWidgets('a name alone does not enable Send for review', (t) async {
      await _pump(
        t,
        const ClaimSubmitScreen(token: 'tok'),
        [
          claimSubmitControllerProvider.overrideWith(
            () => _FixedSubmit(const ClaimSubmitState(name: 'Yusuf Al-Rashid')),
          ),
        ],
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(_submitButton(t, l).onPressed, isNull,
          reason: 'Without a certificate the backend returns a 400 the claimant cannot act on.');
      expect(find.text(l.pcCertRequired), findsOneWidget,
          reason: 'The gate must be visible, not just enforced.');
    });

    testWidgets('a certificate alone does not enable it either — the name is 2..200', (t) async {
      await _pump(
        t,
        const ClaimSubmitScreen(token: 'tok'),
        [
          claimSubmitControllerProvider.overrideWith(
            () => _FixedSubmit(const ClaimSubmitState(name: '', certificate: _cert)),
          ),
        ],
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(_submitButton(t, l).onPressed, isNull);
    });

    testWidgets('name + certificate together enable it', (t) async {
      await _pump(
        t,
        const ClaimSubmitScreen(token: 'tok'),
        [
          claimSubmitControllerProvider.overrideWith(
            () => _FixedSubmit(const ClaimSubmitState(
              name: 'Yusuf Al-Rashid',
              certificate: _cert,
              certificateName: 'certificate.pdf',
            )),
          ),
        ],
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(_submitButton(t, l).onPressed, isNotNull);
      expect(find.text(l.pcCertAttached('certificate.pdf')), findsOneWidget);
      expect(find.text(l.pcCertRequired), findsNothing);
    });

    testWidgets('once attached, no "different file" button is offered', (t) async {
      await _pump(
        t,
        const ClaimSubmitScreen(token: 'tok'),
        [
          claimSubmitControllerProvider.overrideWith(
            () => _FixedSubmit(const ClaimSubmitState(
              name: 'Yusuf Al-Rashid',
              certificate: _cert,
              certificateName: 'certificate.pdf',
            )),
          ),
        ],
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      // Presigns are retryable now (CLAIM_UPLOAD_OPERATION_CAP, 5), so a DROPPED upload no
      // longer burns the link. But the certificate itself is still one per token
      // (CLAIM_CONFIRM_CAP, 1): once one is attached, a second attach would presign happily
      // and then be refused at confirm. Offering that button to someone who has just
      // realised they attached the wrong scan is a dead end dressed up as a fix, so the
      // copy points at the real way out instead.
      expect(find.text(l.pcCertChoose), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text(l.pcCertOnce), findsOneWidget,
          reason: 'The real way out — ask for a fresh link — must be stated instead.');
    });

    // A dead link used to be discovered by the PRESIGN — i.e. after the claimant had typed
    // their legal name, opened the picker and waited while a 4 MB photograph was read into
    // memory. It then appeared as small red body copy under the certificate card, with the
    // form still filled in and no way forward. The recovery copy for exactly this moment
    // was written and translated into both locales and rendered nowhere in the app.
    testWidgets('an invalid link is a dead END, with the way out on screen', (t) async {
      await _pump(
        t,
        const ClaimSubmitScreen(token: 'tok'),
        [
          claimSubmitControllerProvider.overrideWith(
            () => _FixedSubmit(const ClaimSubmitState(step: ClaimSubmitStep.linkDead)),
          ),
        ],
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.text(l.pcLinkInvalidTitle), findsOneWidget);
      expect(find.text(l.pcLinkInvalidSub), findsOneWidget);
      expect(find.text(l.pcStartOver), findsOneWidget);
      // And nothing to fill in: there is nothing to correct and nothing to retry.
      expect(find.text(l.pcNameLbl), findsNothing);
      expect(find.text(l.pcSubmitBtn), findsNothing);
    });

    testWidgets('the form is not offered until the link has been checked', (t) async {
      await _pump(
        t,
        const ClaimSubmitScreen(token: 'tok'),
        [
          claimSubmitControllerProvider.overrideWith(
            () => _FixedSubmit(const ClaimSubmitState(step: ClaimSubmitStep.checking)),
          ),
        ],
        settle: false,
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(l.pcNameLbl), findsNothing);
    });

    testWidgets('the done step thanks the claimant and asks nothing further', (t) async {
      await _pump(
        t,
        const ClaimSubmitScreen(token: 'tok'),
        [
          claimSubmitControllerProvider.overrideWith(
            () => _FixedSubmit(const ClaimSubmitState(step: ClaimSubmitStep.done)),
          ),
        ],
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.text(l.pcDoneTitle), findsOneWidget);
      expect(find.text(l.pcSubmitBtn), findsNothing);
    });
  });

  group('the lookup is not an oracle', () {
    testWidgets('the acknowledgement never confirms that a will exists', (t) async {
      await _pump(
        t,
        const ClaimLookupScreen(),
        [
          claimLookupControllerProvider.overrideWith(
            () => _FixedLookup(const ClaimLookupState(acknowledged: true)),
          ),
        ],
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      expect(find.text(l.pcAckTitle), findsOneWidget);
      // The copy is conditional ("If a will exists…") in every case, because the
      // server's answer is identical in every case.
      expect(l.pcAckBody.toLowerCase(), contains('if a will exists'));

      final shown = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => (w.data ?? '').toLowerCase())
          .join(' | ');
      for (final leak in ['we found', 'no will', 'not found', 'does not exist', 'is registered']) {
        expect(shown.contains(leak), isFalse,
            reason: 'A phrase that distinguishes a match from a miss re-creates the '
                'enumeration oracle the 202-for-everything contract exists to remove.');
      }
    });

    testWidgets('both contacts are needed before Continue is live', (t) async {
      await _pump(
        t,
        const ClaimLookupScreen(),
        [
          claimLookupControllerProvider.overrideWith(
            () => _FixedLookup(const ClaimLookupState(deceasedContact: 'a@b.com')),
          ),
        ],
      );
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      final button = t.widget<FilledButton>(
        find.ancestor(of: find.text(l.pcLookupBtn), matching: find.byType(FilledButton)),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('certificate content types mirror the backend allow-list', () {
    test('only the four accepted kinds map, and they map bare', () {
      // presign compares with `includes(ct)`, so a parameterised type is refused —
      // the bug that broke every non-Safari video upload. These must stay bare.
      expect(deathCertificateContentType('pdf'), 'application/pdf');
      expect(deathCertificateContentType('JPG'), 'image/jpeg');
      expect(deathCertificateContentType('jpeg'), 'image/jpeg');
      expect(deathCertificateContentType('png'), 'image/png');
      expect(deathCertificateContentType('heic'), 'image/heic');
      expect(deathCertificateContentType('mp4'), isNull);
      expect(deathCertificateContentType(null), isNull);

      for (final ct in deathCertificateContentTypes) {
        expect(ct.contains(';'), isFalse, reason: 'A parameterised content type is refused by presign.');
      }
    });
  });
}
