import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/zakat/presentation/zakat_screen.dart';

/// Zakat is opened with `context.go`, which REPLACES the navigation stack — so the
/// AppBar has nothing to pop and the screen had no back affordance at all (the
/// owner's "when zakat is clicked I can't go back"). The opener now passes
/// `?from=<its own path>` and the breadcrumb walks back to it.
///
/// `from` arrives from the URL, so it is untrusted input: on web a user (or a
/// crafted link) can put anything in the query string. These tests pin both the
/// routing behaviour and the refusal to honour an off-app target.
void main() {
  group('ZakatScreen.backTarget — where "‹ Back" returns to', () {
    test('returns to the assets page that opened zakat', () {
      expect(ZakatScreen.backTarget('/wills/w1/assets'), '/wills/w1/assets');
    });

    test('falls back to the dashboard for a direct deep link (no from)', () {
      expect(ZakatScreen.backTarget(null), '/dashboard');
      expect(ZakatScreen.backTarget(''), '/dashboard');
      expect(ZakatScreen.backTarget('   '), '/dashboard');
    });

    test('honours any other in-app path the opener passes', () {
      expect(ZakatScreen.backTarget('/dashboard'), '/dashboard');
      expect(ZakatScreen.backTarget('/vault'), '/vault');
    });

    // The breadcrumb must never become an escape hatch out of the app.
    test('REFUSES a protocol-relative target (//evil.example)', () {
      expect(ZakatScreen.backTarget('//evil.example'), '/dashboard');
      expect(ZakatScreen.backTarget('//evil.example/phish'), '/dashboard');
    });

    test('REFUSES an absolute URL', () {
      expect(ZakatScreen.backTarget('https://evil.example'), '/dashboard');
      expect(ZakatScreen.backTarget('javascript:alert(1)'), '/dashboard');
      expect(ZakatScreen.backTarget('/x://y'), '/dashboard');
    });

    test('REFUSES a relative path that could not be a route', () {
      expect(ZakatScreen.backTarget('dashboard'), '/dashboard');
      expect(ZakatScreen.backTarget('../wills'), '/dashboard');
    });
  });

  /// The whole chain for the one in-app entry point: the assets banner builds the
  /// URL, go_router parses `from` out of it and hands it to ZakatScreen, and the
  /// breadcrumb resolves back to the assets page. Pins the encode/decode round-trip
  /// so a percent-encoded path can't silently degrade to the dashboard fallback.
  group('entry point — assets banner -> zakat -> back to assets', () {
    test('the banner URL round-trips back to the assets page', () {
      // Exactly what _ZakatBanner builds.
      final url = Uri(path: '/zakat', queryParameters: {'from': '/wills/w1/assets'}).toString();
      expect(url, '/zakat?from=%2Fwills%2Fw1%2Fassets');

      // Exactly what the /zakat route hands ZakatScreen.
      final from = Uri.parse(url).queryParameters['from'];
      expect(from, '/wills/w1/assets');
      expect(ZakatScreen.backTarget(from), '/wills/w1/assets');
    });

    test('a deep link with no query lands on the dashboard fallback', () {
      final from = Uri.parse('/zakat').queryParameters['from'];
      expect(ZakatScreen.backTarget(from), '/dashboard');
    });
  });
}
