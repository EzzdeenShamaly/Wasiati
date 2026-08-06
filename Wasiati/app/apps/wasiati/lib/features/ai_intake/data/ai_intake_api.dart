import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../domain/ai_intake_models.dart';

/// Premium+ conversational intake (/ai-intake). The agent extracts structured
/// will data server-side via Claude tool-use; the client only sends plain text
/// (voice-to-text, if used, happens on-device) and renders the reply + running
/// extraction. Gated by the FeatureGuard — a 403 means "upgrade to Premium".
class AiIntakeApi {
  final Dio _dio;
  AiIntakeApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<IntakeTurn> start() => _guard(() async {
        final res = await _dio.post('/ai-intake/start');
        return IntakeTurn.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<IntakeTurn> message(String sessionId, String text) => _guard(() async {
        final res = await _dio.post('/ai-intake/$sessionId/message', data: {'message': text});
        return IntakeTurn.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// Loads a stored session — transcript + extraction — so an interrupted
  /// conversation resumes instead of starting over. 404 when it does not exist
  /// or belongs to another account (the server re-checks ownership).
  Future<IntakeSession> getSession(String sessionId) => _guard(() async {
        final res = await _dio.get('/ai-intake/$sessionId');
        return IntakeSession.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// Closes the conversation and hands back the SEED for the guided form.
  ///
  /// This creates NOTHING. It used to commit a will directly and return its id, which is
  /// why this method read `willId` — but a conversation must not silently produce a legal
  /// document, so the backend now builds no will and returns the counters the wizard
  /// starts from. The owner still walks the form, sees what was understood, and corrects
  /// it before anything is saved. Reading `willId` off this response has been returning
  /// null since that change: the finish button could only throw.
  Future<IntakeSeed> finalize(String sessionId) => _guard(() async {
        final res = await _dio.post('/ai-intake/$sessionId/finalize');
        final body = res.data as Map;
        final seed = (body['seed'] as Map?) ?? const {};
        return IntakeSeed.fromJson(seed.cast<String, dynamic>(), sessionId: body['sessionId'] as String?);
      });

  /// Records WHICH will the seed became, once the wizard has actually saved a draft.
  ///
  /// Separate from finalize() on purpose: only the form knows whether a draft was really
  /// created, and marking it here is what stops one conversation seeding two wills.
  Future<void> markSeeded(String sessionId, String willId) => _guard(() async {
        await _dio.post('/ai-intake/$sessionId/seeded', data: {'willId': willId});
      });
}
