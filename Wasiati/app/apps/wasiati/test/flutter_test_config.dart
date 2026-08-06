import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Global bootstrap for every test in this directory — Flutter looks for this file by name
/// and wraps the whole suite in it.
///
/// It exists for one reason: `SharedPreferences.getInstance()` does not merely FAIL without
/// a platform channel, it HANGS. Any widget that reads a preference on build or in
/// initState therefore leaves a future that never completes and a timer that never fires,
/// so `pumpAndSettle` cannot settle — and the failure surfaces in every unrelated suite
/// that happens to render that widget, not in the one that introduced it. That is a
/// genuinely confusing signal: eight auth suites failed at once for a change to a button's
/// ORDER.
///
/// Installing the plugin's in-memory store here — its own documented seam — makes reads
/// resolve immediately and keeps that class of failure from ever being about the wrong file.
/// A test that cares about specific stored values still calls
/// `SharedPreferences.setMockInitialValues({...})` itself; this only guarantees the channel
/// answers at all.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferences.setMockInitialValues({});
  await testMain();
}
