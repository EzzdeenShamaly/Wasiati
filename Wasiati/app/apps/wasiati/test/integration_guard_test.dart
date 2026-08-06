import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/core/network/api_exception.dart';
import '_integration_guard.dart';

/// The guard exists to stop a throttled run from reporting itself as green. These
/// pin the discrimination, so nobody can widen it back to "skip on any ApiException"
/// without a red test.
void main() {
  group('skipIfBackendDown', () {
    test('429 FAILS loudly — a throttled test did not run and is not a pass', () {
      // The regression this whole guard exists for: the suite exhausts the backend's
      // own 100 req/60s limit, every integration test skips, and the run prints
      // "All tests passed!" having verified nothing.
      expect(
        () => skipIfBackendDown(ApiException('ThrottlerException', statusCode: 429)),
        throwsA(isA<TestFailure>()),
      );
    });

    test('the 429 message says it is not a pass, so the reader cannot mistake it', () {
      try {
        skipIfBackendDown(ApiException('ThrottlerException', statusCode: 429));
        fail('expected a TestFailure');
      } on TestFailure catch (e) {
        expect(e.message, contains('NOT a pass'));
        expect(e.message, contains('429'));
      }
    });

    test('a real API failure (500) rethrows rather than hiding', () {
      expect(
        () => skipIfBackendDown(ApiException('boom', statusCode: 500)),
        throwsA(isA<ApiException>()),
      );
    });

    test('4xx that is not 429 also surfaces — only "no server" is skippable', () {
      expect(
        () => skipIfBackendDown(ApiException('bad request', statusCode: 400)),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => skipIfBackendDown(ApiException('unauthorized', statusCode: 401)),
        throwsA(isA<ApiException>()),
      );
    });

    // The statusCode == null path calls markTestSkipped, which would skip THIS test —
    // it is covered by the integration suite itself, which skips cleanly when no
    // backend is listening (and is the behaviour we deliberately kept).
  });
}
