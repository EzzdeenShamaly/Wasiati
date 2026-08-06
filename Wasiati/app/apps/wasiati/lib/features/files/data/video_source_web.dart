import 'package:video_player/video_player.dart';

/// Builds a player for a just-recorded take on the WEB.
///
/// camera_web returns an `XFile` whose `path` is a `blob:` URL pointing at the recording
/// held in the browser. `networkUrl` fetches it exactly like any other URL, so the take
/// plays without ever leaving the page — and without `dart:io`, which does not exist here.
///
/// The URL is only valid until the screen revokes it (on retake / use / dispose), which is
/// why the widget that owns this is keyed on the path and rebuilt when the take changes.
VideoPlayerController recordedVideoController(String path) =>
    VideoPlayerController.networkUrl(Uri.parse(path));
