import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart'
    show willProvider, witnessesProvider, trusteesProvider;
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/will_detail_screen.dart';

/// The owner's export rule, at the button: a sealed will may always be VIEWED, but
/// "Download PDF" stays DISABLED — with a note naming exactly who is outstanding —
/// until BOTH the witness quorum has signed AND the trustee has confirmed. The
/// backend refuses regardless (WillsService.assertExportable); this pins the client
/// half so the user is told who to chase instead of meeting a 403.

class _FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(AuthUser(id: 'u1', email: 'a@b.test', region: 'US', role: 'USER'));
}

/// A SEALED will — the state in which the Download PDF button is rendered at all.
const _will = Will(
  id: 'w1',
  tier: 'PREMIUM',
  locked: false,
  status: 'SEALED',
  requiredWitnesses: 2,
  shariaShares: [ShariaShare(heirRelation: 'SON', heirName: 'Yusuf', sharePercent: 100)],
);

Future<void> _pumpDetail(
  WidgetTester t, {
  required List<Witness> witnesses,
  required List<Trustee> trustees,
}) async {
  t.view.physicalSize = const Size(1200, 2200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_FakeAuth.new),
      willProvider('w1').overrideWith((ref) async => _will),
      witnessesProvider('w1').overrideWith((ref) async => witnesses),
      trusteesProvider('w1').overrideWith((ref) async => trustees),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const WillDetailScreen(willId: 'w1'),
    ),
  ));
  await t.pumpAndSettle();
}

/// The Download PDF button as the user meets it. `onPressed == null` IS the disabled
/// state in Flutter, so this is the assertion that actually matters.
bool _downloadEnabled(WidgetTester t) {
  final button = t.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Download PDF'),
  );
  return button.onPressed != null;
}

void main() {
  testWidgets('ENABLES Download PDF once both witnesses signed and the trustee confirmed', (t) async {
    await _pumpDetail(t, witnesses: [
      const Witness(id: 'x1', fullName: 'Ibrahim', phone: '+1', status: 'SIGNED'),
      const Witness(id: 'x2', fullName: 'Sara', phone: '+1', status: 'SIGNED'),
    ], trustees: [
      const Trustee(id: 't1', fullName: 'Omar', phone: '+1', status: 'CONFIRMED'),
    ]);

    expect(_downloadEnabled(t), isTrue);
    expect(find.textContaining('Waiting on:'), findsNothing);
  });

  testWidgets('DISABLES with "Waiting on: 1 witness" when a witness has not signed', (t) async {
    await _pumpDetail(t, witnesses: [
      const Witness(id: 'x1', fullName: 'Ibrahim', phone: '+1', status: 'SIGNED'),
      const Witness(id: 'x2', fullName: 'Sara', phone: '+1', status: 'PENDING'),
    ], trustees: [
      const Trustee(id: 't1', fullName: 'Omar', phone: '+1', status: 'CONFIRMED'),
    ]);

    expect(_downloadEnabled(t), isFalse);
    expect(find.text('Waiting on: 1 witness'), findsOneWidget);
  });

  testWidgets('DISABLES with "Waiting on: trustee" when only the trustee is outstanding', (t) async {
    await _pumpDetail(t, witnesses: [
      const Witness(id: 'x1', fullName: 'Ibrahim', phone: '+1', status: 'SIGNED'),
      const Witness(id: 'x2', fullName: 'Sara', phone: '+1', status: 'SIGNED'),
    ], trustees: [
      const Trustee(id: 't1', fullName: 'Omar', phone: '+1', status: 'PENDING'),
    ]);

    expect(_downloadEnabled(t), isFalse);
    expect(find.text('Waiting on: trustee'), findsOneWidget);
  });

  // The owner's own example of the message.
  testWidgets('DISABLES with "Waiting on: 1 witness · trustee" when both are outstanding', (t) async {
    await _pumpDetail(t, witnesses: [
      const Witness(id: 'x1', fullName: 'Ibrahim', phone: '+1', status: 'SIGNED'),
      const Witness(id: 'x2', fullName: 'Sara', phone: '+1', status: 'PENDING'),
    ], trustees: [
      const Trustee(id: 't1', fullName: 'Omar', phone: '+1', status: 'PENDING'),
    ]);

    expect(_downloadEnabled(t), isFalse);
    expect(find.text('Waiting on: 1 witness · trustee'), findsOneWidget);
  });

  testWidgets('DISABLES with "Waiting on: 2 witnesses · trustee" on a will with nothing done', (t) async {
    await _pumpDetail(t, witnesses: [], trustees: []);

    expect(_downloadEnabled(t), isFalse);
    expect(find.text('Waiting on: 2 witnesses · trustee'), findsOneWidget);
  });
}
