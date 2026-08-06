import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Mic dictation + spoken replies for the Ameen intake screen.
///
/// Degrades gracefully everywhere: on Flutter web it drives the browser's Web
/// Speech API; if the platform/browser has no speech engine, or the user denies
/// the mic, [available] stays false and the caller simply hides the mic button —
/// typing always works. Every call is wrapped so a missing engine can never throw
/// into the UI.
class AmeenVoice {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  bool get available => _ready;
  bool get isListening => _stt.isListening;

  /// Probe for a speech engine + mic permission. Safe to call once at boot.
  Future<bool> init() async {
    try {
      _ready = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Start dictation. [onResult] receives the recognized text as it grows;
  /// [languageCode] is 'ar' or 'en'. No-op if speech isn't available.
  Future<void> listen({required String languageCode, required void Function(String) onResult}) async {
    if (!_ready) return;
    try {
      await _stt.listen(
        onResult: (r) => onResult(r.recognizedWords),
        listenOptions: SpeechListenOptions(
          localeId: languageCode == 'ar' ? 'ar_SA' : 'en_US',
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (_) {/* ignore — the button just won't capture */}
  }

  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }

  /// Speak [text] aloud in the app's language (ar-SA / en-US). Best-effort.
  Future<void> speak(String text, {required String languageCode}) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.setLanguage(languageCode == 'ar' ? 'ar-SA' : 'en-US');
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _stt.cancel();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
