import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/settings/presentation/settings_screen.dart';

/// Privacy and Terms resolved to NOTHING in both directions until July 2026:
/// the landing footer pointed at app.wasiati.com/{terms,privacy} (routes the
/// app never had) while the app's Settings pointed at wasiati.com/{privacy,
/// terms} (pages the landing never had). Each side deferred to the other and
/// both were dead — on a will platform.
///
/// These tests pin every URL the app can produce to a page that actually
/// exists in the repo (Cloudflare Pages serves /privacy from privacy.html),
/// and pin the landing footers to their own local pages so the circle cannot
/// quietly re-form.
void main() {
  // test cwd = app/apps/wasiati; the landing lives at the monorepo root.
  final landing = Directory('../../../landing/public');

  test('legalUrl builds the locale-correct marketing-site URL', () {
    expect(legalUrl('en', 'privacy'), 'https://wasiati.com/privacy');
    expect(legalUrl('en', 'terms'), 'https://wasiati.com/terms');
    expect(legalUrl('ar', 'privacy'), 'https://wasiati.com/ar/privacy');
    expect(legalUrl('ar', 'terms'), 'https://wasiati.com/ar/terms');
  });

  test('every URL the app can produce maps onto a real landing page', () {
    const pathOf = {
      'https://wasiati.com/privacy': 'privacy.html',
      'https://wasiati.com/terms': 'terms.html',
      'https://wasiati.com/ar/privacy': 'ar/privacy.html',
      'https://wasiati.com/ar/terms': 'ar/terms.html',
    };
    for (final lang in ['en', 'ar']) {
      for (final page in ['privacy', 'terms']) {
        final url = legalUrl(lang, page);
        final file = File('${landing.path}/${pathOf[url]}');
        expect(file.existsSync(), isTrue,
            reason: '$url is linked from Settings but ${file.path} does not exist — '
                'the link is dead again.');
        final html = file.readAsStringSync();
        expect(html.contains('<h1>'), isTrue, reason: '${file.path} has no heading.');
        expect(html.length, greaterThan(2000),
            reason: '${file.path} looks like a stub, not a real policy.');
      }
    }
  });

  test('the landing footers link their own local pages, not dead app routes', () {
    for (final index in ['index.html', 'ar/index.html']) {
      final html = File('${landing.path}/$index').readAsStringSync();
      expect(html.contains('app.wasiati.com/terms'), isFalse,
          reason: '$index still points Terms at an app route that does not exist.');
      expect(html.contains('app.wasiati.com/privacy'), isFalse,
          reason: '$index still points Privacy at an app route that does not exist.');
      final prefix = index.startsWith('ar/') ? '/ar' : '';
      expect(html.contains('href="$prefix/terms"'), isTrue, reason: '$index lost its Terms link.');
      expect(html.contains('href="$prefix/privacy"'), isTrue,
          reason: '$index lost its Privacy link.');
    }
  });

  test('the four legal pages cross-link consistently (lang switch + footer)', () {
    expect(File('${landing.path}/privacy.html').readAsStringSync(), contains('href="/ar/privacy"'));
    expect(File('${landing.path}/terms.html').readAsStringSync(), contains('href="/ar/terms"'));
    expect(File('${landing.path}/ar/privacy.html').readAsStringSync(), contains('href="/privacy"'));
    expect(File('${landing.path}/ar/terms.html').readAsStringSync(), contains('href="/terms"'));
  });
}
