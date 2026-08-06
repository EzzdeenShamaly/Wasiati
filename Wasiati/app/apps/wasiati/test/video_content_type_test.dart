import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/files/presentation/video_messages_card.dart';

/// Only the backend-allowed video types may be offered; anything else is rejected
/// before an upload is even attempted.
void main() {
  test('maps allowed video extensions to their content-types', () {
    expect(videoContentType('mp4'), 'video/mp4');
    expect(videoContentType('MP4'), 'video/mp4');
    expect(videoContentType('webm'), 'video/webm');
    expect(videoContentType('mov'), 'video/quicktime');
  });

  test('returns null for disallowed or missing extensions', () {
    expect(videoContentType('exe'), isNull);
    expect(videoContentType('avi'), isNull);
    expect(videoContentType(''), isNull);
    expect(videoContentType(null), isNull);
  });
}
