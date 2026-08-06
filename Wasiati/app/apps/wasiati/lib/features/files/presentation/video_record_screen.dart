import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../application/files_providers.dart';
import '../domain/camera_release.dart';
import '../domain/file_models.dart';
// camera_web leaks a blob: URL per recording; free it ourselves.
import '../data/blob_url_stub.dart' if (dart.library.html) '../data/blob_url_web.dart';
// A recorded take is a file path on native and a blob: URL on web, and dart:io does not
// exist on the web at all — so the player is built behind the same conditional import.
import '../data/video_source_stub.dart' if (dart.library.html) '../data/video_source_web.dart';

/// Records a legacy video via the device/browser camera + mic, then uploads it
/// through the same presign→PUT→confirm pipeline as a picked file. Enforces nothing
/// itself — the backend's 1 GB quota and type allow-list still apply on confirm.
///
/// The prototype has no camera screen of its own: it records inline, inside the will's
/// video step. So the LAYOUT here is the platform convention — the viewfinder owns the
/// frame and the controls float over it on a scrim — while what the controls borrow from
/// that video step is their TREATMENT: the terracotta record dot, the rail-green rolling
/// bar with its pulsing dot, the gold timer. The labels stay this screen's existing vr*
/// strings ("Start recording", "Stop"), not the prototype's ("Record video", "Stop &
/// save") — restyling the controls was this sweep's business, renaming them is not.
///
/// Camera behaviour is platform-specific and can't be exercised in unit tests; the
/// error states (no camera, denied permission, camera busy, insecure origin) are
/// handled explicitly so a failure is a clear message, never a blank screen.
class VideoRecordScreen extends ConsumerStatefulWidget {
  const VideoRecordScreen({super.key});
  @override
  ConsumerState<VideoRecordScreen> createState() => _VideoRecordScreenState();
}

/// The rolling clock, mm:ss — Arabic-Indic in AR, where the prototype writes durations
/// that way (its heir video reads ٠٢:١٤). [localizeDigits] carries the AR mapping.
String formatRecordingClock(Duration elapsed, String languageCode) {
  String two(int n) => n.toString().padLeft(2, '0');
  return localizeDigits('${two(elapsed.inMinutes)}:${two(elapsed.inSeconds % 60)}', languageCode);
}

class _VideoRecordScreenState extends ConsumerState<VideoRecordScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool _initializing = true;
  bool _recording = false;
  bool _uploading = false;

  /// A start/stop is in flight. Both calls cross a platform channel and are slow
  /// enough to double-tap through, which would start a second recorder over the
  /// first — and on web, orphan the take.
  bool _busy = false;

  /// That same operation, as a future rather than a flag. [_release] has to *wait*
  /// for the round-trip to land, which a bool cannot express — see there.
  Future<void>? _inFlight;

  /// The in-flight teardown, for [_resume] to wait on.
  Future<void>? _releasing;

  /// The owner turned the camera off from the button, as opposed to the app being
  /// backgrounded. Kept separate from `_controller == null` for two reasons: it must
  /// survive the teardown that nulls the controller, and it tells [_resume] not to
  /// switch the camera back on behind the owner's back when they return to the tab.
  bool _cameraOff = false;

  String? _error;
  XFile? _recorded;
  Timer? _tick;
  Duration _elapsed = Duration.zero;

  /// Every camera on the machine, and which one is open. `availableCameras()` already
  /// returned all of them; the list was simply discarded, so a laptop with a built-in
  /// webcam and a better external one had no way to choose between them.
  List<CameraDescription> _cameras = const [];
  CameraDescription? _selected;

  /// The take is paused. Recording a message to your family is not something most people
  /// can do in one unbroken hour — this is for stopping to collect yourself without losing
  /// what you have already said.
  bool _paused = false;

  /// Gentle pulse for the timer over the final minutes. Slow and shallow on purpose: a hard
  /// blink while someone is talking to their children would be its own small cruelty.
  AnimationController? _pulse;

  /// Whole seconds until the recorder stops itself. Clamped at zero so the last tick
  /// before the auto-stop cannot render a negative countdown.
  int get _secondsLeft {
    final left = maxRecordingDuration.inSeconds - _elapsed.inSeconds;
    return left < 0 ? 0 : left;
  }

  /// Warn over the final [recordingWarnBefore] — five minutes, which on an hour-long
  /// message is enough to finish the thought and say goodbye.
  bool get _nearMaxLength => _recording && _secondsLeft <= recordingWarnBefore.inSeconds;

  /// mm:ss remaining. "300s left" is not a thing anyone reads as five minutes.
  String get _timeLeftLabel {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 1.4s each way: a slow breath, not a strobe.
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _error = context.l10n.vrNoCamera;
          _initializing = false;
        });
        return;
      }
      // KEEP the list. It used to be discarded here, which is why there was no way to
      // pick a different webcam: the screen knew about every camera on the machine for
      // exactly one statement and then threw them all away.
      _cameras = cameras;
      // A message for your family is a selfie: prefer the front lens. availableCameras()
      // documents no ordering, and in practice lists the REAR camera first on both iOS
      // and Android — so `cameras.first` pointed the wrong way round on every phone.
      // Desktop webcams report no facingMode and come back as `external`, so the
      // orElse keeps today's behaviour there.
      final lens = _selected ??
          cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => cameras.first,
          );
      // Pin the bitrate. camera_web's ResolutionPreset→bitrate mapping is dead code
      // (mapResolutionPresetToVideoBitrate is never called), so without this the
      // browser default of ~2.5 Mbps applies — 19 MB/min, all of which we later hold
      // in memory to upload. 1.2 Mbps is ample for a talking head and roughly halves it.
      final controller = CameraController(
        lens,
        ResolutionPreset.high,
        enableAudio: true,
        videoBitrate: 1200000,
        audioBitrate: 96000,
      );
      await controller.initialize();
      // If the user left while initialize() was in flight, the local controller is
      // never assigned to _controller and dispose() can't reach it — dispose it here
      // so the camera + mic are released, not held until GC.
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _selected = lens;
        _initializing = false;
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _error = _messageFor(e);
          _initializing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = context.l10n.vrPermission;
          _initializing = false;
        });
      }
    }
  }

  /// Maps a [CameraException] to something true.
  ///
  /// Every failure used to read "grant camera access", which is actively wrong for
  /// the most common one — another app already holding the camera — and sends the
  /// user to re-grant a permission they already gave.
  ///
  /// Two vocabularies arrive here. camera_web rethrows a raw DOMException as
  /// `CameraException(e.name, ...)` (camera_web.dart:192) but its own
  /// CameraWebException as `CameraException(e.code.toString(), ...)` (:197), so the
  /// same failure can surface as either 'NotReadableError' or 'cameraNotReadable'
  /// depending on which layer caught it. Mobile adds its own codes again.
  String _messageFor(CameraException e) {
    final l = context.l10n;
    return switch (e.code) {
      'CameraAccessDenied' ||
      'CameraAccessDeniedWithoutPrompt' ||
      'CameraAccessRestricted' ||
      'AudioAccessDenied' ||
      'AudioAccessDeniedWithoutPrompt' ||
      'AudioAccessRestricted' ||
      'NotAllowedError' ||
      'PermissionDeniedError' =>
        l.vrPermission,
      'cameraNotFound' || 'NotFoundError' || 'DevicesNotFoundError' => l.vrNoCamera,
      'cameraNotReadable' || 'NotReadableError' || 'TrackStartError' => l.vrBusy,
      // camera_web maps a JS TypeError here, which is what an insecure origin looks
      // like: navigator.mediaDevices is undefined off https/localhost.
      'cameraType' || 'TypeError' => l.vrInsecure,
      'cameraNotSupported' ||
      'cameraSecurity' ||
      'SecurityError' ||
      'cameraOverconstrained' ||
      'OverconstrainedError' ||
      'ConstraintNotSatisfiedError' =>
        l.vrUnsupported,
      _ => l.vrPermission,
    };
  }

  /// Release the camera while the app is away, and rebuild it on return.
  ///
  /// Without this the OS revokes the camera on background and the preview comes back
  /// dead. An in-flight take cannot survive it either — camera_web nulls its
  /// MediaRecorder without stopping it — so stop first and keep what was recorded.
  ///
  /// Deliberately NOT `inactive`: on web that fires on mere window blur, so releasing
  /// there would tear the camera down every time a desktop user glanced at another
  /// window. `hidden`/`paused` are the states where the camera is actually taken away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      if (c != null && c.value.isInitialized) _releasing = _release(c);
    } else if (state == AppLifecycleState.resumed) {
      _resume();
    }
  }

  /// Stop cleanly, then hand the camera back. [_stop] is awaited before dispose so
  /// the take is captured rather than torn out from under the recorder.
  ///
  /// [_inFlight] is awaited first because `_recording` is not yet true in the middle
  /// of [_start]: the recorder is already coming up, but the flag that says so is set
  /// only once the round-trip lands. Reading the flag here skipped the stop and
  /// disposed the camera underneath it — [_start] then resumed against a dead
  /// controller, and the resume built a second one while the pill and the clock went
  /// on claiming a take that no longer existed. Backgrounding does not unmount, so
  /// [_start]'s own `mounted` check never caught this.
  Future<void> _release(CameraController c) async {
    await _inFlight;
    _tick?.cancel();
    if (_recording) await _stop();
    _controller = null;
    await c.dispose();
    if (mounted) setState(() {});
  }

  /// Rebuild the camera [_release] handed back.
  ///
  /// Waits for the teardown rather than reading `_controller`, which is nulled only
  /// once the stop has landed: a resume arriving inside that window would see a camera
  /// that is already doomed, decline to re-init, and leave a dead preview behind a
  /// Record button that silently does nothing.
  Future<void> _resume() async {
    await _releasing;
    // A camera the owner switched off stays off. Without this, returning to the tab
    // would silently re-acquire the device and relight the lamp they just put out.
    if (!mounted || _controller != null || _error != null || _cameraOff) return;
    setState(() => _initializing = true);
    _init();
  }

  /// Turn the camera off — really off, device released and light out — or back on.
  ///
  /// There was no such control. Stop only ends the TAKE; the preview and therefore the
  /// camera stay live so another take can start, which is right for a recorder and
  /// indistinguishable, from the outside, from the app ignoring you: the owner reported
  /// the camera showing as off in the app while the webcam light stayed on.
  ///
  /// Off goes through the same [_release] the lifecycle uses, so any take in progress is
  /// stopped and kept before the device is handed back.
  Future<void> _toggleCamera() async {
    if (_cameraOff) {
      setState(() {
        _cameraOff = false;
        _initializing = true;
      });
      await _init();
      return;
    }
    final c = _controller;
    setState(() => _cameraOff = true);
    if (c != null && c.value.isInitialized) {
      _releasing = _release(c);
      await _releasing;
    }
  }

  /// Opens a DIFFERENT camera, releasing the current one first.
  ///
  /// Order matters and is the same rule as everywhere else on this screen: a device that
  /// is still held cannot be reopened, and on web the old MediaStream would keep its
  /// tracks live — the webcam light staying on next to a preview showing the other camera.
  /// [releaseCamera] (via [_release]) stops any take first, so this is safe even if the
  /// picker is somehow reached mid-recording.
  Future<void> _switchCamera(CameraDescription next) async {
    if (next.name == _selected?.name || _busy) return;
    final c = _controller;
    setState(() {
      _selected = next;
      _controller = null;
      _initializing = true;
      _cameraOff = false;
    });
    if (c != null) {
      _releasing = _release(c);
      await _releasing;
    }
    await _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _pulse?.dispose();
    final rec = _recorded;
    if (rec != null) revokeBlobUrl(rec.path);

    // Leaving mid-take used to leave the camera ON — the page was gone and the webcam
    // light stayed lit.
    //
    // This called `_controller?.dispose()` directly, which is precisely the case
    // didChangeAppLifecycleState already documents above: camera_web nulls its
    // MediaRecorder WITHOUT stopping it, so disposing during a take leaves the recorder
    // holding the MediaStream and its tracks are never stopped. _release() stops the
    // take first for exactly this reason; dispose() skipped that and went straight to
    // disposal.
    //
    // dispose() cannot await, so the teardown is handed to a detached future over a
    // CAPTURED controller — `this` is dead the moment super.dispose() runs, but the
    // local reference keeps the camera reachable until it is properly released.
    final c = _controller;
    _controller = null;
    if (c != null) unawaited(_shutDown(c));

    super.dispose();
  }

  /// Stop the take, then hand the camera back. Safe to call after this State is disposed:
  /// it touches only the controller passed in, never the widget tree. The ordering rule
  /// and the reason for it live in [releaseCamera], where they can be tested.
  static Future<void> _shutDown(CameraController c) => releaseCamera(
        isRecording: () => c.value.isRecordingVideo,
        stop: c.stopVideoRecording,
        dispose: c.dispose,
      );

  /// Pause or resume, keeping everything recorded so far.
  ///
  /// Offered on every platform this app ships to, web included. The control used to be
  /// hidden on web behind a claim that camera_web's plugin class never overrides
  /// pauseVideoRecording, leaving the call to die on CameraPlatform's UnimplementedError
  /// default. That claim is FALSE for the versions this app resolves: CameraPlugin does
  /// override pause and resume (camera_web 0.3.5, camera_web.dart:522/534) and hands them
  /// to Camera.pauseVideoRecording → MediaRecorder.pause() (camera.dart:542/552). One
  /// MediaRecorder session spans every pause, so stop still concatenates chunks of a
  /// single container stream — ONE continuous playable file with the paused stretch
  /// simply absent. No segments, nothing to merge, no second recording stack to own.
  /// test/web_camera_pause_chrome_test.dart drives that exact plugin chain over a real
  /// MediaRecorder in Chrome and measures that paused wall time records no footage.
  ///
  /// A failure leaves the take RECORDING rather than in a state the owner cannot read:
  /// if the platform refuses the pause, the honest thing is that nothing changed.
  Future<void> _togglePause() async {
    final c = _controller;
    if (c == null || !_recording || _busy) return;
    final wantPause = !_paused;
    try {
      if (wantPause) {
        await c.pauseVideoRecording();
      } else {
        await c.resumeVideoRecording();
      }
      if (mounted) setState(() => _paused = wantPause);
    } catch (e) {
      if (mounted) {
        WasiatiSnack.danger(context, e is CameraException ? _messageFor(e) : context.l10n.vrPauseFailed);
      }
    }
  }

  /// Start or stop the take, one at a time.
  ///
  /// Holds the operation's future instead of dropping it on the floor: [_release] is
  /// the one caller that cannot act on `_recording` alone, and this is the only handle
  /// on the round-trip it has to wait for.
  void _toggle() {
    if (_busy) return;
    _inFlight = _recording ? _stop() : _start();
  }

  Future<void> _start() async {
    final c = _controller;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      await c.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _paused = false;
        _elapsed = Duration.zero;
      });
      _pulse?.stop();
      _pulse?.value = 1.0;
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        // A paused take is not recording, so it must not consume the hour. The clock and
        // the cap both count actual footage, which is what the owner is watching.
        if (_paused) return;
        setState(() => _elapsed += const Duration(seconds: 1));
        // Start the pulse once inside the warning window, and only once.
        if (_nearMaxLength && _pulse?.isAnimating != true) {
          _pulse?.repeat(reverse: true);
        }
        // Stop AT the cap rather than letting the take run to the 500 MB file limit.
        //
        // Without this a recording could run ~55 minutes at the pinned 1.2 Mbps before
        // anything refused it — and the whole blob is held in memory to upload, so a long
        // take is also the most likely way this screen runs a phone out of RAM. Nobody
        // intends a fifty-minute message to their family either; the useful ones are short.
        //
        // Auto-stop, not a refusal: the take so far is KEPT and offered for review, because
        // discarding what someone just recorded to their children would be the worse bug.
        if (_elapsed >= maxRecordingDuration && !_busy) {
          WasiatiSnack.success(context, context.l10n.vrMaxLengthReached);
          _toggle();
        }
      });
    } on CameraException catch (e) {
      // A snackbar, not _error: the camera is alive and the preview is worth keeping.
      // Only a failure to *acquire* the camera earns the full-screen state, which is
      // terminal — it would strand the user here with no way to retry.
      if (mounted) WasiatiSnack.danger(context, _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final c = _controller;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    _tick?.cancel();
    _pulse?.stop();
    _paused = false;
    try {
      // camera_web completes this future only inside `if (_videoData.isNotEmpty)`
      // (camera.dart:500-518), so a stop that yields no blob never completes and
      // would strand the UI on a dead Stop button with the take unreachable. Time
      // it out and surface the failure instead of hanging.
      final file = await c.stopVideoRecording().timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recorded = file;
      });
    } on TimeoutException {
      // The take is gone, but the camera isn't — drop back to idle so they can go
      // again, rather than stranding them on a Stop button that will never resolve.
      if (mounted) {
        setState(() => _recording = false);
        WasiatiSnack.danger(context, context.l10n.vrFailed);
      }
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _recording = false);
        WasiatiSnack.danger(context, _messageFor(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retake() {
    final rec = _recorded;
    // Drop the blob before the reference goes: camera_web never revokes it, so each
    // retake would otherwise pin another whole video for the life of the page.
    if (rec != null) revokeBlobUrl(rec.path);
    setState(() {
      _recorded = null;
      _elapsed = Duration.zero;
    });
  }

  Future<void> _use() async {
    final rec = _recorded;
    if (rec == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;

    // Size first. On web this is blob.size — it costs nothing and materialises
    // nothing, whereas readAsBytes() below pulls the entire video onto the heap.
    // presign would reject an oversized take anyway, but only after we had paid for
    // the read, so check the ceiling while it is still free.
    final size = await rec.length();
    if (size > videoLegacyMaxBytes) {
      if (mounted) WasiatiSnack.danger(context, l.vrTooLarge);
      return;
    }

    setState(() => _uploading = true);
    try {
      // readAsBytes() already returns a Uint8List — the old Uint8List.fromList(bytes)
      // around it copied the whole video a second time for nothing.
      final bytes = await rec.readAsBytes();
      await ref.read(fileUploaderProvider).upload(
            kind: 'video_legacy',
            // Strips camera_web's `;codecs="vp9,opus"`, which the backend's exact-match
            // allow-list rejects. See videoUploadContentType.
            contentType: videoUploadContentType(rec.mimeType),
            bytes: bytes,
          );
      ref.invalidate(storageQuotaProvider);
      ref.invalidate(videoFilesProvider);
      // Uploaded and owned by the backend now — let the blob go.
      revokeBlobUrl(rec.path);
      if (mounted) {
        _recorded = null;
        WasiatiSnack.success(context, l.vidUploaded);
        context.go('/legacy');
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.vrTitle),
        // Explicit, because go() leaves nothing to pop and AppBar's automatic
        // leading would render as nothing — stranding whoever opened the recorder
        // to look at it and thought better of filming.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          tooltip: l.commonBackToLegacy,
          onPressed: () => context.go('/legacy'),
        ),
      ),
      // bottom: false — the shell's frosted bar overlaps the body, and the viewfinder
      // runs on down behind it so the glass has the live camera to frost. The controls
      // floating over it carry the bar's height instead (see AppShell's extendBody).
      body: SafeArea(bottom: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_initializing) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(_error!, textAlign: TextAlign.center, style: t.bodyLarge?.copyWith(color: context.tokens.muted)),
        ),
      );
    }

    // Once there is a take, the frame belongs to the TAKE, not the live camera.
    //
    // This is the playback bug: the recorded file was held in `_recorded` and the
    // controls switched to Retake/Use, but the frame behind them kept showing the live
    // preview — so "review" showed you the camera you were still sitting in front of,
    // and the recording itself could not be watched anywhere before committing to it.
    final rec = _recorded;
    return Stack(fit: StackFit.expand, children: [
      if (rec != null && !_uploading) _RecordedPreview(key: ValueKey(rec.path), path: rec.path) else _viewfinder(),
      Align(alignment: Alignment.bottomCenter, child: _controls(context)),
    ]);
  }

  /// Covers rather than letterboxes: the camera fills the frame edge to edge, so the
  /// strip behind the glass bar is live image rather than a dead black bar.
  Widget _viewfinder() {
    final c = _controller;
    return ColoredBox(
      color: Colors.black,
      child: c == null
          // Says WHY the frame is dark. A black rectangle is what a broken preview looks
          // like too, and the difference matters when the question in the owner's mind is
          // "is this thing still watching me".
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.videocam_off_outlined,
                    size: 34, color: WasiatiColors.onDark.withValues(alpha: 0.7)),
                if (_cameraOff) ...[
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.vrCameraOffNote,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: WasiatiType.bodyFamily,
                      fontFamilyFallback: const [WasiatiType.arabicFamily, WasiatiType.arabicSerifFamily],
                      color: WasiatiColors.onDark.withValues(alpha: 0.8),
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ]),
            )
          : ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                // FittedBox scales whatever it is handed, so this box only has to carry
                // the camera's aspect ratio — the absolute size is arbitrary.
                child: SizedBox(
                  width: c.value.aspectRatio * 1000,
                  height: 1000,
                  child: CameraPreview(c),
                ),
              ),
            ),
    );
  }

  /// The controls float over the viewfinder rather than taking height from it, on a
  /// scrim that keeps them legible against whatever the camera is pointed at.
  Widget _controls(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 34, 20, 20 + MediaQuery.paddingOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Only while there is nothing recorded to review — turning the camera off with a
        // take waiting would suggest the take goes with it, and it does not.
        if (_recorded == null && !_uploading) ...[
          Row(children: [
            _cameraToggle(context),
            const Spacer(),
            _cameraPicker(context),
          ]),
          const SizedBox(height: 12),
        ],
        _uploading
            ? _uploadingRow(context)
            : _recorded != null
                ? _reviewRow(context)
                : _recording
                    ? _rollingBar(context)
                    : _recordButton(context),
      ]),
    );
  }

  /// Turns the camera off for real, and says which state it is in.
  ///
  /// Hidden while recording: stopping the take is the Stop chip's job, and a control that
  /// silently ends a recording is worse than no control.
  Widget _cameraToggle(BuildContext context) {
    if (_recording) return const SizedBox.shrink();
    final l = context.l10n;
    final off = _cameraOff;
    // No Align: the row in _controls positions this against the camera picker.
    return TextButton.icon(
      onPressed: _toggleCamera,
      icon: Icon(off ? Icons.videocam_off_outlined : Icons.videocam_outlined, size: 17),
      label: Text(off ? l.vrCameraOn : l.vrCameraOff),
      style: _overlayButtonStyle(),
    );
  }

  static ButtonStyle _overlayButtonStyle() => TextButton.styleFrom(
        foregroundColor: WasiatiColors.onDark,
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontFamily: WasiatiType.bodyFamily,
          fontFamilyFallback: [WasiatiType.arabicFamily, WasiatiType.arabicSerifFamily],
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );

  /// Choose which camera records — the second half of the reported bug.
  ///
  /// Hidden when there is nothing to choose between (one camera) and while a take is
  /// rolling, where swapping the device mid-recording would end it. Labels come from the
  /// lens direction where the platform reports one, and fall back to the device name,
  /// which is what a desktop browser gives for an external webcam.
  Widget _cameraPicker(BuildContext context) {
    if (_recording || _cameras.length < 2) return const SizedBox.shrink();
    final l = context.l10n;
    return PopupMenuButton<CameraDescription>(
      tooltip: l.vrSwitchCamera,
      onSelected: _switchCamera,
      itemBuilder: (context) => [
        for (final cam in _cameras)
          PopupMenuItem(
            value: cam,
            child: Row(children: [
              Icon(
                cam.name == _selected?.name ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 16,
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(_cameraLabel(context, cam))),
            ]),
          ),
      ],
      child: IgnorePointer(
        child: TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.cameraswitch_outlined, size: 17),
          label: Text(l.vrSwitchCamera),
          style: _overlayButtonStyle(),
        ),
      ),
    );
  }

  String _cameraLabel(BuildContext context, CameraDescription cam) {
    switch (cam.lensDirection) {
      case CameraLensDirection.front:
        return context.l10n.vrLensFront;
      case CameraLensDirection.back:
        return context.l10n.vrLensBack;
      case CameraLensDirection.external:
        // A desktop webcam's own label ("HD Pro Webcam C920") is more useful than
        // anything we could invent, and is what the browser reports.
        return cam.name.isEmpty ? context.l10n.vrSwitchCamera : cam.name;
    }
  }

  /// The prototype's rolling state, restyled onto this screen's strings: a rail-green bar
  /// carrying the pulsing terracotta dot, the status line, the gold timer and the stop chip.
  Widget _rollingBar(BuildContext context) {
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: WasiatiColors.railGreen, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const _PulsingDot(size: 10),
        const SizedBox(width: 12),
        Expanded(
          child: Text(l.vrRecording,
              style: const TextStyle(
                fontFamily: WasiatiType.bodyFamily,
                color: WasiatiColors.onDark,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              )),
        ),
        const SizedBox(width: 12),
        // Over the last five minutes the clock turns terracotta and breathes. The recorder
        // stops itself at the hour, and an auto-stop nobody saw coming reads as the app
        // cutting them off mid-sentence.
        FadeTransition(
          opacity: _nearMaxLength
              ? Tween<double>(begin: 0.55, end: 1.0)
                  .animate(CurvedAnimation(parent: _pulse!, curve: Curves.easeInOut))
              : const AlwaysStoppedAnimation<double>(1.0),
          child: Text(
            formatRecordingClock(_elapsed, Localizations.localeOf(context).languageCode),
            // A clock still counts up left-to-right in Arabic; only the digits localise.
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontFamily: WasiatiType.displayFamily,
              color: _nearMaxLength ? WasiatiColors.danger : WasiatiColors.goldDeepDark,
              fontSize: 14,
            ),
          ),
        ),
        if (_nearMaxLength) ...[
          const SizedBox(width: 8),
          Text(
            context.digits(context.l10n.vrTimeLeft(_timeLeftLabel)),
            style: const TextStyle(
              fontFamily: WasiatiType.bodyFamily,
              color: WasiatiColors.onDark,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        // Pause sits before Stop so the gentler action is the one nearer the thumb.
        // On every platform, web included — see _togglePause for the receipts.
        const SizedBox(width: 8),
        IconButton(
          onPressed: _busy ? null : _togglePause,
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          tooltip: _paused ? context.l10n.vrResume : context.l10n.vrPause,
          icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: WasiatiColors.onDark),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: _toggle,
          // The stop-square carries the affordance (WCAG 1.4.11 graphical, 3:1) so it
          // never rests on the label. Red is the universal recording-stop convention —
          // kept from the prototype, not swapped to the primary green (DECISIONS §14).
          icon: const Icon(Icons.stop, size: 15),
          style: FilledButton.styleFrom(
            // recordStopField, not record: the label deepens the fill to clear AA (4.94:1
            // under onDark), where the raw #C46B5C dot could carry no label at all.
            backgroundColor: WasiatiColors.recordStopField,
            foregroundColor: WasiatiColors.onDark,
            // The prototype's chip is 31px tall; the default padded tap target keeps the
            // touch box at 48 without inflating it.
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            // Naming a family in a BUTTON's textStyle costs the theme's Arabic fallback:
            // ButtonStyle hands this to Material, which replaces the ambient DefaultTextStyle
            // rather than merging into it, so "إيقاف" would render through Public Sans alone.
            // (The plain Texts above merge, and keep the fallback for free.) Same list as
            // theme.dart's — IBM Plex Sans Arabic for UI, Amiri only for rare marks.
            textStyle: const TextStyle(
              fontFamily: WasiatiType.bodyFamily,
              fontFamilyFallback: [WasiatiType.arabicFamily, WasiatiType.arabicSerifFamily],
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          label: Text(l.vrStop),
        ),
      ]),
    );
  }

  /// The idle record button in the prototype's treatment — bottle green, terracotta dot.
  Widget _recordButton(BuildContext context) {
    final l = context.l10n;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _toggle,
        icon: Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(color: WasiatiColors.record, shape: BoxShape.circle),
        ),
        label: Text(l.vrStart),
        style: FilledButton.styleFrom(
          backgroundColor: WasiatiColors.bottleGreen,
          foregroundColor: WasiatiColors.onDark,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          // Fallback for the same reason as the stop chip's: "ابدأ التسجيل" is Arabic copy.
          textStyle: const TextStyle(
            fontFamily: WasiatiType.bodyFamily,
            fontFamilyFallback: [WasiatiType.arabicFamily, WasiatiType.arabicSerifFamily],
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _reviewRow(BuildContext context) {
    final l = context.l10n;
    return Row(children: [
      Expanded(
        child: OutlinedButton(
          onPressed: _retake,
          style: OutlinedButton.styleFrom(
            foregroundColor: WasiatiColors.onDark,
            side: BorderSide(color: WasiatiColors.onDark.withValues(alpha: 0.5)),
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
          child: Text(l.vrRetake),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: FilledButton(
          onPressed: _use,
          style: FilledButton.styleFrom(
            backgroundColor: WasiatiColors.bottleGreen,
            foregroundColor: WasiatiColors.onDark,
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
          child: Text(l.vrUse),
        ),
      ),
    ]);
  }

  Widget _uploadingRow(BuildContext context) {
    final l = context.l10n;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: WasiatiColors.onDark),
      ),
      const SizedBox(width: 12),
      Text(l.vrUploading,
          style: const TextStyle(
            fontFamily: WasiatiType.bodyFamily,
            color: WasiatiColors.onDark,
            fontWeight: FontWeight.w600,
          )),
    ]);
  }
}

/// The prototype's `pulse 1.2s ease infinite` on the rolling dot: opacity 1 → .45 → 1.
class _PulsingDot extends StatefulWidget {
  final double size;
  const _PulsingDot({required this.size});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.45).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: const BoxDecoration(color: WasiatiColors.record, shape: BoxShape.circle),
      ),
    );
  }
}

/// Plays a just-recorded take back, before the owner commits to it.
///
/// This is what the review step was missing. The recording was captured and held, and the
/// controls offered Retake / Use — but nothing ever rendered the file, so the only way to
/// find out what you had recorded was to send it to your family.
///
/// The source is whatever the camera plugin handed back: on web a `blob:` URL, which
/// [VideoPlayerController.networkUrl] can fetch, and on native a file path. The blob is
/// revoked by the screen on retake/use/dispose, so this widget must be rebuilt (keyed on
/// the path) whenever the take changes rather than reusing a controller over a dead URL.
class _RecordedPreview extends StatefulWidget {
  const _RecordedPreview({super.key, required this.path});
  final String path;

  @override
  State<_RecordedPreview> createState() => _RecordedPreviewState();
}

class _RecordedPreviewState extends State<_RecordedPreview> {
  VideoPlayerController? _player;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    // Web hands back a blob: URL, native a file path — resolved by conditional import so
    // this file never mentions dart:io. Both are supported: the recorder runs in the web
    // app and in the mobile companion.
    final controller = recordedVideoController(widget.path);
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      // Loop quietly rather than autoplay with sound: the owner is usually still sitting
      // in front of the machine they just recorded on, and blasting their own voice back
      // at full volume is startling. They press play when ready.
      await controller.setLooping(true);
      setState(() => _player = controller);
    } catch (_) {
      await controller.dispose();
      // A take that cannot be PREVIEWED is still a take that SAVED. Say so, and leave
      // Use enabled — refusing the upload because the browser cannot decode its own
      // recording would lose a message that is perfectly fine on the server.
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    if (_failed) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              context.l10n.vrPlaybackFailed,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: WasiatiType.bodyFamily,
                fontFamilyFallback: const [WasiatiType.arabicFamily, WasiatiType.arabicSerifFamily],
                color: WasiatiColors.onDark.withValues(alpha: 0.85),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ),
      );
    }
    if (p == null) {
      return const ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator()));
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        // Matches the viewfinder's cover framing so the take occupies the frame exactly
        // as the live preview did — the review should look like what you just shot.
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: p.value.aspectRatio * 1000,
              height: 1000,
              child: VideoPlayer(p),
            ),
          ),
        ),
        // The play/pause affordance, and a heading so the frame is unambiguously the
        // RECORDING rather than the camera still watching you.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.l10n.vrReviewTake,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: WasiatiType.bodyFamily,
                  fontFamilyFallback: const [WasiatiType.arabicFamily, WasiatiType.arabicSerifFamily],
                  color: WasiatiColors.onDark.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        Center(
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: p,
            builder: (context, value, _) => IconButton(
              iconSize: 64,
              color: WasiatiColors.onDark.withValues(alpha: 0.92),
              icon: Icon(value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
              onPressed: () => value.isPlaying ? p.pause() : p.play(),
            ),
          ),
        ),
      ]),
    );
  }
}
