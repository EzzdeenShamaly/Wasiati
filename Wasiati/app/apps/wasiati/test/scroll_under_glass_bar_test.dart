import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati/core/providers.dart';
import 'package:wasiati/core/shell/app_shell.dart';
import 'package:wasiati/features/ai_intake/application/ai_intake_providers.dart';
import 'package:wasiati/features/ai_intake/data/ai_intake_api.dart';
import 'package:wasiati/features/ai_intake/domain/ai_intake_models.dart';
import 'package:wasiati/features/ai_intake/presentation/ai_intake_screen.dart';
import 'package:wasiati/features/auth/application/auth_controller.dart';
import 'package:wasiati/features/auth/domain/auth_state.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/commerce/application/commerce_providers.dart';
import 'package:wasiati/features/commerce/domain/commerce_models.dart';
import 'package:wasiati/features/commerce/presentation/admin/admin_console_screen.dart';
import 'package:wasiati/features/vault/presentation/vault_screen.dart';
import 'package:wasiati/features/wills/application/wills_providers.dart' show willsListProvider;
import 'package:wasiati/features/wills/domain/wills_models.dart';
import 'package:wasiati/features/wills/presentation/wills_list_screen.dart';

/// The frosted nav bar is only frosted if there is something live behind it.
///
/// AppShell sets `extendBody: true`, which hands the bar's height to the body as
/// MediaQuery.padding.bottom. A screen that spends that on a plain SafeArea insets
/// its own VIEWPORT: content then stops dead at the bar's top edge and the blur
/// samples a flat scaffold. Spending it on the scrolled CONTENT instead keeps the
/// viewport full-bleed — rows pass under the glass — while the last row still comes
/// to rest clear of the bar.
///
/// Both halves are pinned here: a full-bleed viewport alone would hide the final
/// rows behind the bar at max scroll, which is the other way to get this wrong.
/// This is invisible to the golden captures, so it is asserted geometrically.

const _screen = Size(420, 780);

class _FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(AuthUser(id: 'u1', email: 'a@b.test', region: 'US', role: 'USER'));
}

/// Ameen's opening turn, so the chat renders instead of its boot spinner. Overriding
/// the API wholesale keeps the test off the network — and off apiClientProvider, which
/// would want a token store.
class _FakeIntakeApi extends AiIntakeApi {
  _FakeIntakeApi() : super(Dio());
  @override
  Future<IntakeTurn> start() async => const IntakeTurn(
        sessionId: 's1',
        reply: 'Tell me about your family.',
        extracted: ExtractedData(),
        completed: false,
      );
}

const _promos = [
  Promotion(id: 'p1', code: 'WELCOME10', type: 'PERCENT', value: 10, active: true, timesRedeemed: 3),
];

/// Enough wills to overflow a 780px-tall phone, so there is a real scroll extent.
final _wills = [
  for (var i = 0; i < 2; i++)
    Will(id: 'w$i', tier: 'PREMIUM', locked: true, status: 'SEALED', updatedAt: DateTime(2026, 5, 3)),
];

Future<void> _pump(
  WidgetTester t, {
  required String location,
  required Widget screen,
  List<Override> overrides = const [],
}) async {
  t.view.physicalSize = _screen;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(_FakeAuth.new),
      willsListProvider.overrideWith((ref) async => _wills),
      ...overrides,
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppShell(location: location, child: screen),
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _pumpShell(WidgetTester t) =>
    _pump(t, location: '/wills', screen: const WillsListScreen());

void main() {
  // AiIntakeScreen reads SharedPreferences on boot to resume an interrupted Ameen
  // session. Without a mock store the plugin channel never answers, _boot() never
  // finishes, the screen sits on its loading spinner, and pumpAndSettle times out —
  // which reads as a layout failure but is really a missing test double. Empty map =
  // no saved session, so the screen takes the fresh-start path.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the scroll viewport runs full-bleed UNDER the frosted bar', (t) async {
    await _pumpShell(t);

    final barTop = t.getRect(find.byType(NavigationBar)).top;
    final viewportBottom = t.getRect(find.byType(SingleChildScrollView)).bottom;

    // The bar overlaps the body rather than sitting below it.
    expect(barTop, lessThan(_screen.height), reason: 'the bar should be on screen');
    // The regression: viewport stopping exactly at the bar's top edge (barTop), so
    // nothing ever passes beneath the blur.
    expect(viewportBottom, _screen.height,
        reason: 'viewport must reach the bottom of the screen, not stop at the bar ($barTop)');
  });

  testWidgets('content still comes to rest clear of the bar at max scroll', (t) async {
    await _pumpShell(t);

    final barTop = t.getRect(find.byType(NavigationBar)).top;
    final scrollable = find.byType(Scrollable).first;
    final position = t.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0), reason: 'need a real scroll extent to test');

    // Scroll to the very end.
    position.jumpTo(position.maxScrollExtent);
    await t.pumpAndSettle();

    // The last thing on the wills screen is the healthcare-directive card.
    final lastCard = find.byType(WasiatiCard).last;
    expect(t.getRect(lastCard).bottom, lessThanOrEqualTo(barTop),
        reason: 'the last card must not be stranded behind the bar at max scroll');
  });

  testWidgets('mid-scroll, content genuinely sits beneath the glass', (t) async {
    await _pumpShell(t);

    final barTop = t.getRect(find.byType(NavigationBar)).top;
    final viewport = t.getRect(find.byType(SingleChildScrollView));
    final position = t.state<ScrollableState>(find.byType(Scrollable).first).position;

    // Halfway down: something should be crossing under the bar.
    position.jumpTo(position.maxScrollExtent / 2);
    await t.pumpAndSettle();

    final underGlass = find.byType(WasiatiCard).evaluate().where((e) {
      final box = e.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      // Clip to the viewport: a card scrolled past a short viewport still reports
      // its full un-clipped rect, so raw geometry would "pass" on the very bug
      // this pins. Only the part that actually paints counts.
      final painted = rect.intersect(viewport);
      return painted.height > 0 && painted.bottom > barTop;
    });
    expect(underGlass, isNotEmpty,
        reason: 'nothing paints below the bar mid-scroll — the blur has nothing to sample');
  });

  // The vault's unlock view is a Center, so its scroll view deliberately shrink-wraps
  // rather than filling the viewport — there is nothing to scroll under the bar while
  // the card fits. What matters is that it did not DRIFT when the viewport went
  // full-bleed. The scroll view shrink-wraps to content + the bar's height, so Center
  // hands back exactly the offset the inset viewport used to provide; drop that bottom
  // padding and the card sinks half the bar's height toward the middle of the screen.
  testWidgets('vault: the unlock card stays optically centred above the bar', (t) async {
    await _pump(t, location: '/vault', screen: const VaultScreen());
    final barTop = t.getRect(find.byType(NavigationBar)).top;
    final card = t.getRect(
        find.descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Column)).first);

    expect(card.center.dy, moreOrLessEquals(barTop / 2, epsilon: 1.0),
        reason: 'the card must stay centred in the space above the bar, not sink toward '
            'the full-height centre (${_screen.height / 2})');
  });

  // Ameen's chat is the one screen where the pattern inverts. Its composer is PINNED
  // below the chat list, so the list never reaches the bar and padding it would achieve
  // nothing — the composer is what owes the bar its height. Both halves fail loudly:
  // leave the SafeArea alone and the composer stops at the bar (dead strip under the
  // glass); add `bottom: false` without padding the composer and the send button lands
  // underneath the bar, out of reach.
  testWidgets('ai intake: the pinned composer carries the bar, its controls stay clear', (t) async {
    await _pump(t,
        location: '/intake',
        screen: const AiIntakeScreen(),
        overrides: [aiIntakeApiProvider.overrideWithValue(_FakeIntakeApi())]);

    final barTop = t.getRect(find.byType(NavigationBar)).top;
    // The composer's own Container: the nearest Container above the chat input.
    final composer = t.getRect(
        find.ancestor(of: find.byType(TextField), matching: find.byType(Container)).first);

    expect(composer.bottom, _screen.height,
        reason: 'the composer surface must run to the screen bottom so the glass frosts it, '
            'rather than stopping at the bar ($barTop) and leaving a dead strip');
    expect(t.getRect(find.byIcon(Icons.arrow_upward)).bottom, lessThanOrEqualTo(barTop),
        reason: 'the send button must stay above the bar, not be stranded under the glass');
  });

  // The admin console's promo tab floats a FAB against its OWN Scaffold, which runs
  // full-bleed once the console's SafeArea stops insetting it. Scaffold lifts a FAB clear
  // of viewPadding, but the shell's bar arrives as padding — so the FAB needs lifting by
  // hand, and without it the button parks under the glass.
  testWidgets('admin console: the new-promo FAB floats above the bar, not under it', (t) async {
    await _pump(t, location: '/admin', screen: const AdminConsoleScreen(), overrides: [
      adminPlansProvider.overrideWith((ref) async => []),
      adminPromotionsProvider.overrideWith((ref) async => _promos),
      adminOffersProvider.overrideWith((ref) async => []),
    ]);
    // The FAB lives on the Promotions tab (the second of the three).
    await t.tap(find.byType(Tab).at(1));
    await t.pumpAndSettle();

    final barTop = t.getRect(find.byType(NavigationBar)).top;
    expect(t.getRect(find.byType(FloatingActionButton)).bottom, lessThanOrEqualTo(barTop),
        reason: 'the new-promo button must stay above the bar, not park under the glass');
  });
}
