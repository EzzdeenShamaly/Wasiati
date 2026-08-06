// The camera is actually RELEASED — the webcam light goes out.
//
// The owner reported the app showing the camera as off while the webcam light stayed on.
// Two separate causes:
//
// 1. dispose() called `_controller?.dispose()` directly, without stopping an in-flight
//    take first. That is exactly the case didChangeAppLifecycleState documents in the
//    recorder screen: camera_web nulls its MediaRecorder WITHOUT stopping it, so disposing
//    during a recording leaves the recorder holding the MediaStream and its tracks never
//    stop. _release() had always stopped the take first; dispose() did not. So: record,
//    press back, page gone, light still on.
//
// 2. There was no camera off control at all. Stop ends the TAKE and deliberately keeps the
//    preview alive so another take can start — correct for a recorder, and from the
//    outside indistinguishable from the app ignoring you.
//
// These exercise releaseCamera() itself — the function the screen actually calls — rather
// than a copy of its logic. The real CameraController needs a platform channel and a
// browser, so the operations are injected; the ORDER, which is the whole bug, is real.

import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/files/domain/camera_release.dart';

/// Stands in for CameraController, recording the teardown calls in order.
class _FakeCamera {
  _FakeCamera({this.recording = false, this.stopThrows = false, this.disposeThrows = false});

  bool recording;
  final bool stopThrows;
  final bool disposeThrows;
  bool disposed = false;
  final List<String> calls = [];

  Future<void> stop() async {
    calls.add('stop');
    if (stopThrows) throw StateError('recorder already gone with the page');
    recording = false;
  }

  Future<void> dispose() async {
    calls.add('dispose');
    if (disposeThrows) throw StateError('controller already torn down');
    disposed = true;
  }

  Future<void> release() => releaseCamera(
        isRecording: () => recording,
        stop: stop,
        dispose: dispose,
      );
}

void main() {
  test('a take in progress is stopped BEFORE the camera is disposed', () async {
    final c = _FakeCamera(recording: true);
    await c.release();
    expect(c.calls, ['stop', 'dispose'],
        reason: 'disposing first leaves camera_web holding an unstopped recorder, and the '
            'MediaStream tracks with it — which is the lit-light bug');
    expect(c.disposed, isTrue);
  });

  test('an idle camera is disposed without a spurious stop', () async {
    final c = _FakeCamera();
    await c.release();
    expect(c.calls, ['dispose']);
    expect(c.disposed, isTrue);
  });

  test('a controller that throws on stop is STILL disposed', () async {
    // The important one. If a failing stop could skip disposal, every error path would
    // leave the device open — the exact outcome this code exists to prevent.
    final c = _FakeCamera(recording: true, stopThrows: true);
    await c.release();
    expect(c.calls, ['stop', 'dispose']);
    expect(c.disposed, isTrue, reason: 'a failed stop must never cost us the disposal');
  });

  test('a dispose that throws does not escape — teardown runs from dispose()', () async {
    // releaseCamera is called from State.dispose(), which cannot await and cannot catch.
    // An escaping error there becomes an unhandled async exception rather than anything
    // the owner or we can act on.
    final c = _FakeCamera(recording: true, disposeThrows: true);
    await expectLater(c.release(), completes);
  });
}
