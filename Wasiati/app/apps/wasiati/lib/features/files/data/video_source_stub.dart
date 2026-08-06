import 'dart:io';

import 'package:video_player/video_player.dart';

/// Builds a player for a just-recorded take on NATIVE platforms, where the camera
/// plugin hands back a real file path.
///
/// This is the default half of a conditional import (`video_source_web.dart` is the
/// other), mirroring how `blob_url_stub.dart` is paired in this feature. It exists
/// because `dart:io` does not compile for the web at all, so a single file cannot
/// reference both `File` and the browser path.
VideoPlayerController recordedVideoController(String path) =>
    VideoPlayerController.file(File(path));
