@TestOn('browser')
library;

// The whole point of this file is to test the REAL camera_web internals — the exact
// bytes the app ships — not a reimplementation of them, so the src/ imports are the test.
// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:js_interop';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:camera_web/camera_web.dart';
import 'package:camera_web/src/camera.dart';
import 'package:camera_web/src/camera_service.dart';
import 'package:camera_web/src/types/types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/files/domain/file_models.dart';
import 'package:web/web.dart' as web;

/// Proves, in a real Chrome, that the resolved camera_web plugin pauses for real.
///
/// The record screen used to hide Pause on web behind a claim that CameraPlugin never
/// overrides pauseVideoRecording, so the call would die on CameraPlatform's
/// UnimplementedError default. This suite runs the ACTUAL plugin — the same
/// CameraPlugin the generated web registrant installs — over a canvas-captured
/// MediaStream (the one camera a headless browser has), through the same three calls
/// the screen makes: startVideoCapturing → pauseVideoRecording / resumeVideoRecording
/// → stopVideoRecording.
///
/// What it pins:
///  * pause/resume reach MediaRecorder.pause()/resume() — observable as the recorder's
///    own state flipping recording → paused → recording, with no UnimplementedError;
///  * ONE MediaRecorder session spans the pause, so the stop hands back ONE continuous
///    playable file — its decoded duration counts only footage, not paused wall time;
///  * the take's mime survives [videoUploadContentType] into the backend allow-list.
///
/// Runs under `flutter test --platform chrome`; the VM run skips it via @TestOn.
/// What it cannot prove: getUserMedia against a physical webcam and mic — no headless
/// environment has one. That last inch is manual.
void main() {
  test('pause is wired through the plugin, not UnimplementedError', () async {
    // No recorder yet: the pre-pause failure must be camera_web's own typed exception
    // ("the recording might not have been started"), which exists only inside the
    // override the record screen was told is missing.
    final CameraPlugin plugin = CameraPlugin(cameraService: CameraService());
    plugin.cameras[1] = Camera(textureId: 1, cameraService: CameraService());
    expect(
      () => plugin.pauseVideoRecording(1),
      throwsA(isA<CameraWebException>()
          .having((e) => e.code, 'code', CameraErrorCode.videoRecordingNotStarted)),
    );
    expect(() => plugin.resumeVideoRecording(1), throwsA(isA<CameraWebException>()));
  });

  test('one recorder session across pause/resume yields one continuous file', () async {
    // A canvas is the only MediaStream source that needs no permission prompt and no
    // hardware; keep painting so captureStream has frames to hand the recorder.
    final web.HTMLCanvasElement canvas = web.HTMLCanvasElement()
      ..width = 320
      ..height = 240;
    final web.CanvasRenderingContext2D ctx =
        canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    int frame = 0;
    void paint() {
      ctx.fillStyle = 'hsl(${(frame * 11) % 360}, 80%, 50%)'.toJS;
      ctx.fillRect(0, 0, 320, 240);
      frame++;
    }

    paint();
    final Timer painter = Timer.periodic(const Duration(milliseconds: 40), (_) => paint());
    final web.MediaStream stream = canvas.captureStream(15);

    // The same shape the app builds: pinned bitrates, and the stream sitting where
    // startVideoRecording expects it (videoElement.srcObject).
    final Camera camera = Camera(
      textureId: 7,
      cameraService: CameraService(),
      recorderOptions: (audioBitrate: 96000, videoBitrate: 1200000),
    );
    camera.videoElement = web.HTMLVideoElement()..srcObject = stream;

    final CameraPlugin plugin = CameraPlugin(cameraService: CameraService());
    plugin.cameras[7] = camera;

    try {
      await plugin.startVideoCapturing(const VideoCaptureOptions(7));
      expect(camera.mediaRecorder, isNotNull);
      expect(camera.mediaRecorder!.state, 'recording');
      await Future<void>.delayed(const Duration(milliseconds: 900));

      // The exact calls CameraController makes on the screen's behalf.
      await plugin.pauseVideoRecording(7);
      expect(camera.mediaRecorder!.state, 'paused');
      // Paused wall time, long enough to dominate the recording if pause were fake.
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      await plugin.resumeVideoRecording(7);
      expect(camera.mediaRecorder!.state, 'recording');
      await Future<void>.delayed(const Duration(milliseconds: 900));

      final XFile file = await plugin.stopVideoRecording(7);

      // One take, one blob URL, and bytes actually in it.
      expect(file.path, startsWith('blob:'));
      expect(await file.readAsBytes(), isNotEmpty);
      // The mime it reports is the mime it recorded, and the upload path's
      // normalisation lands it inside the backend's exact-match allow-list.
      expect(videoLegacyContentTypes, contains(videoUploadContentType(file.mimeType)));

      // ~1.8s of footage across ~3.4s of wall time. A merge-free TRUE pause decodes to
      // roughly the footage; a recorder that kept rolling would decode to the wall
      // time. The bounds are deliberately loose — headless frame pacing wobbles — but
      // they cannot both hold unless the paused stretch is absent from the file.
      final double seconds = await _playableDurationSeconds(file.path);
      expect(seconds, greaterThan(0.3));
      expect(seconds, lessThan(2.8));

      // Same discipline the screen keeps: the blob dies with the test.
      web.URL.revokeObjectURL(file.path);
    } finally {
      painter.cancel();
      // And the release rule from camera_release.dart: every track stopped, always.
      stream.getTracks().toDart.forEach((web.MediaStreamTrack t) => t.stop());
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Decoded duration of a recorded blob, via the browser's own demuxer.
///
/// Chrome's MediaRecorder writes no duration into the webm header (crbug.com/642012),
/// so a fresh recording reports Infinity; seeking far past the end forces the real
/// value to be computed.
Future<double> _playableDurationSeconds(String blobUrl) async {
  final web.HTMLVideoElement video = web.HTMLVideoElement()..preload = 'metadata';
  final Completer<void> loaded = Completer<void>();
  video.addEventListener(
    'loadedmetadata',
    ((web.Event _) {
      if (!loaded.isCompleted) loaded.complete();
    }).toJS,
  );
  video.src = blobUrl;
  await loaded.future.timeout(const Duration(seconds: 15));
  if (!video.duration.isFinite) {
    final Completer<void> sought = Completer<void>();
    video.addEventListener(
      'seeked',
      ((web.Event _) {
        if (!sought.isCompleted) sought.complete();
      }).toJS,
    );
    video.currentTime = 1e7;
    await sought.future.timeout(const Duration(seconds: 15));
  }
  return video.duration;
}
