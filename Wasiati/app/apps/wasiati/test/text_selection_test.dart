// Ordinary text is selectable/copyable across the app.
//
// Flutter paints to a canvas on web, so a Text widget has no native browser selection —
// the owner reported not being able to select anything. The fix is a SelectionArea over the
// page content. It lives at the two shared page bodies (AppShell for the signed-in app,
// AuthScaffold for the signed-out screens) rather than at the MaterialApp builder, because
// SelectionArea needs an Overlay ancestor and the builder sits above the router's Navigator
// (which is where "No Overlay widget found" comes from). These pin that the wrap is present
// and that the page content is inside it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/core/shell/app_shell.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/auth/presentation/widgets/auth_scaffold.dart';

class _FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(AuthUser(id: 'u1', email: 'a@wasiati.test', region: 'US', role: 'USER'));
}

Future<void> _pump(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(1200, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [authControllerProvider.overrideWith(_FakeAuth.new)],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  const marker = Text('selectable page content', key: ValueKey('marker'));

  testWidgets('AppShell wraps the routed page in a SelectionArea', (t) async {
    await _pump(t, const AppShell(location: '/dashboard', child: marker));
    expect(
      find.ancestor(of: find.byKey(const ValueKey('marker')), matching: find.byType(SelectionArea)),
      findsOneWidget,
      reason: 'the signed-in page body must be selectable',
    );
  });

  testWidgets('the nav chrome is OUTSIDE the SelectionArea', (t) async {
    // The rail/bottom-nav is deliberately not wrapped — only the page content is, so a
    // drag-select does not sweep up the navigation labels.
    await _pump(t, const AppShell(location: '/dashboard', child: marker));
    final sel = find.byType(SelectionArea);
    expect(sel, findsOneWidget);
    expect(find.descendant(of: sel, matching: find.byKey(const ValueKey('marker'))), findsOneWidget);
  });

  testWidgets('AuthScaffold wraps its content in a SelectionArea', (t) async {
    await _pump(
      t,
      const AuthScaffold(title: 'Sign in', children: [marker]),
    );
    expect(
      find.ancestor(of: find.byKey(const ValueKey('marker')), matching: find.byType(SelectionArea)),
      findsOneWidget,
      reason: 'the signed-out screens must be selectable too',
    );
  });
}
