import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/content/application/content_providers.dart';

/// The "ARB default + admin override" decision (docs/DECISIONS.md §4): a published
/// override wins in the current locale; otherwise the bundled ARB fallback is used,
/// so the app always renders — offline, on first paint, or if the fetch fails.

/// Renders [overrideText] inside a scope whose overrides provider is forced to a
/// fixed async value, then returns the resolved string.
Future<String> resolve(
  WidgetTester tester, {
  required AsyncValue<Map<String, ({String en, String ar})>> value,
  required String key,
  required String fallback,
  required bool isRtl,
}) async {
  late String result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [contentOverridesProvider.overrideWith((ref) => _fixed(value))],
      child: Consumer(
        builder: (context, ref, _) {
          result = overrideText(ref, key: key, fallback: fallback, isRtl: isRtl);
          return const SizedBox();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return result;
}

// A FutureProvider override needs a Future; complete it immediately (or never, for
// the loading case) to model each AsyncValue state.
Future<Map<String, ({String en, String ar})>> _fixed(
  AsyncValue<Map<String, ({String en, String ar})>> v,
) {
  return v.when(
    data: (m) => Future.value(m),
    error: (e, _) => Future.error(e),
    loading: () => Completer<Map<String, ({String en, String ar})>>().future, // never completes
  );
}

void main() {
  const ovr = {'sealWry': (en: 'EN override', ar: 'تجاوز عربي')};

  testWidgets('uses the published override in the CURRENT locale', (t) async {
    expect(
      await resolve(t, value: const AsyncData(ovr), key: 'sealWry', fallback: 'fb', isRtl: false),
      'EN override',
    );
    expect(
      await resolve(t, value: const AsyncData(ovr), key: 'sealWry', fallback: 'fb', isRtl: true),
      'تجاوز عربي',
    );
  });

  testWidgets('falls back to the ARB value when no override exists for the key', (t) async {
    expect(
      await resolve(t, value: const AsyncData({}), key: 'sealWry', fallback: 'ARB default', isRtl: false),
      'ARB default',
    );
  });

  testWidgets('falls back while the fetch is still loading (first paint / offline)', (t) async {
    expect(
      await resolve(t, value: const AsyncLoading(), key: 'sealWry', fallback: 'ARB default', isRtl: false),
      'ARB default',
    );
  });

  testWidgets('falls back when the fetch FAILS — never blanks the UI', (t) async {
    expect(
      await resolve(t, value: const AsyncError('offline', StackTrace.empty), key: 'sealWry', fallback: 'ARB default', isRtl: false),
      'ARB default',
    );
  });

  testWidgets('a blank/whitespace override does not blank the UI', (t) async {
    const blank = {'sealWry': (en: '   ', ar: '')};
    expect(
      await resolve(t, value: const AsyncData(blank), key: 'sealWry', fallback: 'ARB default', isRtl: false),
      'ARB default',
    );
  });
}
