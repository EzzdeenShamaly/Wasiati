/// Handing the camera back, in the one order that actually turns the light off.
///
/// Extracted from the recorder screen so the ORDER can be tested. It cannot be exercised
/// through the widget: CameraController needs a platform channel and a real browser, so a
/// widget test can only ever assert against a re-implementation of this logic — which is a
/// green test that proves nothing about the code that ships.
///
/// The rule: stop any take FIRST, then dispose, and let neither failure prevent the other.
///
/// Disposing while a take is running is the whole bug. camera_web nulls its MediaRecorder
/// without stopping it, so the recorder keeps the MediaStream, its tracks are never
/// stopped, and the webcam light stays on after the page is gone. The screen's lifecycle
/// handler had always stopped the take first for this reason; dispose() went straight to
/// disposal, so leaving mid-recording leaked the device.
///
/// Errors are swallowed on purpose. A controller that throws on the way down must still
/// reach dispose, or an error path leaves the camera open — the exact outcome this exists
/// to prevent. There is nothing useful to tell the owner either: by the time this runs the
/// screen is usually gone.
Future<void> releaseCamera({
  required bool Function() isRecording,
  required Future<void> Function() stop,
  required Future<void> Function() dispose,
}) async {
  try {
    if (isRecording()) await stop();
  } catch (_) {
    // Already stopped, or the recorder died with the page. Disposal still has to happen.
  }
  try {
    await dispose();
  } catch (_) {}
}
