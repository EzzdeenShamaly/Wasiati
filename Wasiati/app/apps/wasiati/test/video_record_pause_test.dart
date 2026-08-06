import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/files/presentation/video_record_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

/// Pause/resume on the record screen: the clock, the cap, and the failure contract.
///
/// The clock and the one-hour cap both count FOOTAGE, not wall time — someone who
/// pauses to collect themselves must not watch their remaining hour drain while they
/// are not saying anything. And a platform that refuses to pause must leave the take
/// RECORDING and say so, never silently half-paused.
///
/// The web half of this feature — that the resolved camera_web plugin really routes
/// pause/resume to MediaRecorder.pause()/resume() rather than CameraPlatform's
/// UnimplementedError default — cannot run in the VM; it lives in
/// web_camera_pause_chrome_test.dart under `flutter test --platform chrome`.

/// Answers instantly everywhere and counts what the screen asks of the platform.
class _FakeCamera extends CameraPlatform {
  int pauses = 0;
  int resumes = 0;
  int stops = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
        CameraDescription(name: 'front', lensDirection: CameraLensDirection.front, sensorOrientation: 0),
      ];

  @override
  Future<int> createCameraWithSettings(CameraDescription description, MediaSettings? mediaSettings) async => 1;

  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) => Stream<CameraInitializedEvent>.value(
      const CameraInitializedEvent(1, 640, 480, ExposureMode.auto, true, FocusMode.auto, true));

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() => const Stream<DeviceOrientationChangedEvent>.empty();

  @override
  Widget buildPreview(int cameraId) => const SizedBox();

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {}

  @override
  Future<void> pauseVideoRecording(int cameraId) async {
    pauses++;
  }

  @override
  Future<void> resumeVideoRecording(int cameraId) async {
    resumes++;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    stops++;
    return XFile('/take.webm', mimeType: 'video/webm;codecs="vp9,opus"');
  }

  @override
  Future<void> dispose(int cameraId) async {}
}

/// The web plugin BEFORE this feature existed, as the platform interface models it:
/// no pause override at all, so the call dies on the base class's UnimplementedError.
/// Kept as a fake so the failure contract — still recording, told honestly — stays
/// pinned even though no shipped platform behaves this way any more.
class _PauselessCamera extends _FakeCamera {
  @override
  Future<void> pauseVideoRecording(int cameraId) => throw UnimplementedError('pauseVideoRecording() is not implemented.');
}

Future<void> _pumpRecorder(WidgetTester t, _FakeCamera cam) async {
  CameraPlatform.instance = cam;
  await t.pumpWidget(ProviderScope(
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const VideoRecordScreen(),
    ),
  ));
  // availableCameras() → initialize() → first frame with a preview. Not pumpAndSettle:
  // the record dot pulses forever, so settling never returns.
  await t.pump();
  await t.pump();
  await t.pump();
}

Future<void> _startRecording(WidgetTester t) async {
  await t.tap(find.text('Start recording'));
  await t.pump();
  await t.pump();
  expect(find.text('Recording…'), findsOneWidget);
}

void main() {
  testWidgets('pausing freezes the clock; resuming picks it back up', (t) async {
    final cam = _FakeCamera();
    await _pumpRecorder(t, cam);
    await _startRecording(t);

    await t.pump(const Duration(seconds: 3));
    expect(find.text('00:03'), findsOneWidget);

    await t.tap(find.byTooltip('Pause'));
    await t.pump();
    expect(cam.pauses, 1);
    // The affordance flips: what is offered now is the way back.
    expect(find.byTooltip('Resume'), findsOneWidget);

    // Five paused seconds are NOT footage. The ticker keeps running (it is what notices
    // the resume) but the clock it renders must not move.
    await t.pump(const Duration(seconds: 5));
    expect(find.text('00:03'), findsOneWidget);
    expect(find.text('00:08'), findsNothing);

    await t.tap(find.byTooltip('Resume'));
    await t.pump();
    expect(cam.resumes, 1);
    await t.pump(const Duration(seconds: 2));
    expect(find.text('00:05'), findsOneWidget);

    // The paused-and-resumed take still stops into a reviewable recording.
    await t.tap(find.text('Stop'));
    await t.pump();
    await t.pump();
    expect(cam.stops, 1);
    expect(find.text('Retake'), findsOneWidget);
    expect(find.text('Use this video'), findsOneWidget);
  });

  testWidgets('a paused take does not consume the hour', (t) async {
    final cam = _FakeCamera();
    await _pumpRecorder(t, cam);
    await _startRecording(t);

    await t.pump(const Duration(seconds: 3));
    await t.tap(find.byTooltip('Pause'));
    await t.pump();

    // Two paused HOURS: past the cap twice over in wall time, zero of it footage. The
    // recorder must neither auto-stop nor warn — the owner has said nothing yet.
    await t.pump(const Duration(hours: 2));
    expect(cam.stops, 0);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('00:03'), findsOneWidget);
    expect(find.textContaining('One hour reached'), findsNothing);

    await t.tap(find.byTooltip('Resume'));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(find.text('00:05'), findsOneWidget);
  });

  testWidgets('the cap counts footage and auto-stop keeps the take', (t) async {
    final cam = _FakeCamera();
    await _pumpRecorder(t, cam);
    await _startRecording(t);

    // One hour of actual footage → the recorder stops ITSELF, and what was recorded is
    // kept and offered for review, not discarded.
    await t.pump(const Duration(hours: 1));
    await t.pump();
    await t.pump();
    expect(cam.stops, 1);
    expect(find.textContaining('One hour reached'), findsOneWidget);
    expect(find.text('Retake'), findsOneWidget);
    expect(find.text('Use this video'), findsOneWidget);

    // Let the snackbar's own dismiss timer fire before the tree goes down.
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('a platform that cannot pause leaves the take recording and says so', (t) async {
    final cam = _PauselessCamera();
    await _pumpRecorder(t, cam);
    await _startRecording(t);

    await t.pump(const Duration(seconds: 2));
    await t.tap(find.byTooltip('Pause'));
    await t.pump();

    // Nothing changed, and the owner is told exactly that: still recording, clock still
    // advancing, no phantom half-paused state.
    expect(find.text('That could not be paused. Your recording is still running.'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Resume'), findsNothing);
    await t.pump(const Duration(seconds: 3));
    expect(find.text('00:05'), findsOneWidget);

    // Walk the snackbar off before reaching for Stop — it rests over the bottom
    // controls, so while mounted it eats the tap. Sliced pumps, not one big one: the
    // messenger arms its dismiss timer only on the build AFTER the entrance animation
    // completes, so a single elapse can never both arm the timer and fire it.
    for (var i = 0; i < 8 && t.any(find.byType(SnackBar)); i++) {
      await t.pump(const Duration(seconds: 3));
    }
    expect(find.byType(SnackBar), findsNothing);
    await t.tap(find.text('Stop'));
    await t.pump();
    await t.pump();
    expect(cam.stops, 1);
  });
}
