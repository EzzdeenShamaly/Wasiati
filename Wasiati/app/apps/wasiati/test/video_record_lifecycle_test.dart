import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/files/presentation/video_record_screen.dart';
import 'package:wasiati/l10n/app_localizations.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

/// The record screen's lifecycle seam: the app going away *while a start is still
/// crossing the platform channel*.
///
/// That window is the whole point. Outside it the screen has a flag — `_recording` —
/// that says whether a recorder is up, and the release can read it. Inside it the flag
/// lies: the recorder is coming up, but nothing has said so yet. A release that trusts
/// the flag there skips the stop, disposes the camera under a live recorder, and the
/// screen comes back to a pill and a running clock over a take that does not exist.
///
/// Backgrounding does not unmount, so `mounted` checks do not close this. Only waiting
/// for the round-trip does.

/// A camera that answers instantly for everything EXCEPT the start, which is held open
/// until the test says otherwise. Holding it is what puts the test inside the window.
class _FakeCamera extends CameraPlatform {
  /// Completed by the test, not the plugin — so the start stays in flight for exactly
  /// as long as the scenario needs.
  Completer<void> start = Completer<void>();

  int stops = 0;
  int disposals = 0;
  int builds = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
        CameraDescription(name: 'front', lensDirection: CameraLensDirection.front, sensorOrientation: 0),
      ];

  @override
  Future<int> createCameraWithSettings(CameraDescription description, MediaSettings? mediaSettings) async {
    builds++;
    return 1;
  }

  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream<CameraInitializedEvent>.value(const CameraInitializedEvent(1, 640, 480, ExposureMode.auto, true, FocusMode.auto, true));

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() => const Stream<DeviceOrientationChangedEvent>.empty();

  @override
  Widget buildPreview(int cameraId) => const SizedBox();

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) => start.future;

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    stops++;
    return XFile('/take.webm', mimeType: 'video/webm;codecs="vp9,opus"');
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposals++;
  }
}

late _FakeCamera _cam;

/// Builds the fake and mounts the screen.
///
/// The fake is constructed HERE, inside the test body, and deliberately not in a
/// `setUp`: [testWidgets] runs its body in a fake-async zone, and a Completer created
/// outside that zone schedules its continuations on the real microtask queue — which
/// `pump()` does not drain. The start would then never land, no matter how many pumps.
Future<void> _pumpRecorder(WidgetTester t) async {
  _cam = _FakeCamera();
  CameraPlatform.instance = _cam;
  await t.pumpWidget(ProviderScope(
    child: MaterialApp(
      locale: const Locale('en'),
      theme: WasiatiTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const VideoRecordScreen(),
    ),
  ));
  // availableCameras() → CameraController.initialize() → first frame with a preview.
  // Not pumpAndSettle: the record dot pulses forever, so settling never returns.
  await t.pump();
  await t.pump();
  await t.pump();
}

/// Drives the real transition order the framework delivers (resumed → inactive →
/// hidden). The screen ignores `inactive` on purpose — on web it fires on mere window
/// blur — so it must be `hidden` that does the work.
void _background(WidgetTester t) {
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
}

void _foreground(WidgetTester t) {
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  testWidgets('a background inside the start round-trip still stops the recorder', (t) async {
    await _pumpRecorder(t);
    await t.tap(find.text('Start recording'));
    await t.pump();

    // Standing in the window: the channel has not answered, so `_recording` is still
    // false — but a recorder IS coming up on the other side.
    expect(_cam.stops, 0);

    _background(t);
    await t.pump();

    // ...and only now does the start land.
    _cam.start.complete();
    await t.pump();
    await t.pump();

    // The release had to WAIT for that, then stop what it found. Reading `_recording`
    // at background time saw false, skipped this, and disposed the camera underneath
    // a running recorder.
    expect(_cam.stops, 1, reason: 'the in-flight take was never stopped');
    expect(_cam.disposals, 1, reason: 'the camera must still be handed back');
  });

  testWidgets('comes back to the take, not to a phantom recording', (t) async {
    await _pumpRecorder(t);
    await t.tap(find.text('Start recording'));
    await t.pump();
    _background(t);
    await t.pump();
    _cam.start.complete();
    await t.pump();
    await t.pump();

    _foreground(t);
    // The resume rebuilds the camera; let _init() land.
    await t.pump();
    await t.pump();
    await t.pump();

    // What the stop captured is what the user is offered. The old path left `_recording`
    // true against a disposed controller, so this surface showed a pill, a ticking clock
    // and a Stop button that threw a CameraException into a snackbar.
    expect(find.text('Retake'), findsOneWidget);
    expect(find.text('Use this video'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(find.text('Recording…'), findsNothing);
    // A second camera was built for the resumed screen — the first was disposed, not leaked.
    expect(_cam.builds, 2);
    expect(_cam.disposals, 1);
  });

  testWidgets('the ordinary path — no background — is untouched', (t) async {
    await _pumpRecorder(t);
    await t.tap(find.text('Start recording'));
    _cam.start.complete();
    await t.pump();
    await t.pump();

    expect(find.text('Recording…'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    await t.tap(find.text('Stop'));
    await t.pump();
    await t.pump();

    expect(_cam.stops, 1);
    expect(find.text('Retake'), findsOneWidget);
    expect(find.text('Use this video'), findsOneWidget);
  });
}
