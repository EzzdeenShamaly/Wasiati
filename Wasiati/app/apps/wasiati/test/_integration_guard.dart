import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/core/network/api_exception.dart';

/// Decides whether an integration-test failure is a legitimate skip or a real failure.
///
/// These tests talk to a live backend, so they must tolerate "no backend running" —
/// but the original guard skipped on *any* `ApiException`, which quietly swallowed
/// HTTP 429 as well. That mattered: the backend rate-limits globally at 100 req/60s
/// with no test bypass, and the suite exceeds that on its own. The result was a suite
/// that printed "All tests passed!" while the tests had never executed — a green that
/// twice reported work as verified when nothing had run.
///
/// So the rule is narrow: skip ONLY when there is genuinely nothing listening
/// (`statusCode == null` — connection refused / timed out). A 429 means the suite
/// throttled itself, which is a suite defect to fix, not a condition to hide. Every
/// other status is a real API failure and must surface.
///
/// Usage mirrors the old shape:
/// ```dart
/// try {
///   ...
/// } on ApiException catch (e) {
///   skipIfBackendDown(e);
/// }
/// ```
void skipIfBackendDown(ApiException e) {
  if (e.statusCode == null) {
    markTestSkipped('backend not running (${e.message}) — start it to run this test');
    return;
  }
  if (e.statusCode == 429) {
    fail(
      'Rate-limited (429) by the backend, so this test never ran.\n'
      'This is NOT a pass. The global throttle is 100 req/60s and the suite exceeds '
      'it unaided. Re-run this file alone, or raise the dev throttle — do not treat '
      'a throttled run as green.',
    );
  }
  // Any other status is a genuine API failure; let it fail loudly.
  throw e;
}
