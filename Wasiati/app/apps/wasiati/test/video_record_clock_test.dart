import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/files/presentation/video_record_screen.dart';

/// The recording clock is the one number this screen renders, and AR wants it in
/// Arabic-Indic — the prototype's own heir video reads ٠٢:١٤.
///
/// This is pinned because the obvious ways to get it are both wrong: intl's
/// `NumberFormat('00', 'ar')` and `MaterialLocalizations.formatDecimal` each hand back
/// Western digits under the `ar` locale, so a clock built on either looks correct in a
/// review and renders 01:23 to an Arabic reader.
void main() {
  test('counts mm:ss, zero-padded', () {
    expect(formatRecordingClock(Duration.zero, 'en'), '00:00');
    expect(formatRecordingClock(const Duration(seconds: 5), 'en'), '00:05');
    expect(formatRecordingClock(const Duration(minutes: 1, seconds: 23), 'en'), '01:23');
    // Minutes accumulate rather than rolling over at an hour — a legacy message that
    // long is already past every quota, but the clock should still read honestly.
    expect(formatRecordingClock(const Duration(hours: 1, minutes: 5, seconds: 9), 'en'), '65:09');
  });

  test('renders Arabic-Indic digits in AR', () {
    expect(formatRecordingClock(const Duration(minutes: 1, seconds: 23), 'ar'), '٠١:٢٣');
    expect(formatRecordingClock(const Duration(seconds: 5), 'ar'), '٠٠:٠٥');
    // The prototype's own duration, exactly.
    expect(formatRecordingClock(const Duration(minutes: 2, seconds: 14), 'ar'), '٠٢:١٤');
  });
}
