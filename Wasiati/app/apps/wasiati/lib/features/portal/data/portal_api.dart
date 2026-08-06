import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/portal_client.dart';
import '../domain/portal_models.dart';

/// Client for the heir & trustee portal.
///
/// NOT ONE CALL HERE TAKES A WILL IDENTIFIER. Every session read is scoped by the
/// willId inside the token, exactly as the backend controller is written — there is
/// nothing for this client to point at another estate even if it wanted to.
class PortalApi {
  final Dio _dio;
  PortalApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  // --- Public: sign-in --------------------------------------------------------

  /// Sends a code to the contact ON FILE for this party. The backend answers
  /// `{ sent: true }` whether or not the address is on any will, so there is
  /// nothing here to branch on and nothing to report back but success.
  Future<void> start({required PortalRole role, required String email}) => _guard(() async {
        await _dio.post('/portal/start', data: {'role': role.api, 'email': email});
      });

  /// Exchanges the code for a read-only session. EVERY failure — wrong code, no
  /// code pending, expired, attempt cap burned, address on no will — comes back as
  /// the same 400 with the same message. Do not try to tell them apart.
  Future<PortalSession> verify({
    required PortalRole role,
    required String email,
    required String code,
  }) =>
      _guard(() async {
        final res = await _dio.post('/portal/verify', data: {'role': role.api, 'email': email, 'code': code});
        return PortalSession.fromJson((res.data as Map).cast<String, dynamic>());
      });

  // --- Session ----------------------------------------------------------------

  Future<PortalMe> me(String token) => _guard(() async {
        final res = await _dio.get('/portal/me', options: PortalClient.auth(token));
        return PortalMe.fromJson((res.data as Map).cast<String, dynamic>());
      });

  Future<PortalClaim> claim(String token) => _guard(() async {
        final res = await _dio.get('/portal/claim', options: PortalClient.auth(token));
        return PortalClaim.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// HEIR only, APPROVED only. Idempotent — a second tap returns 201 and does not
  /// rewrite the original timestamp.
  Future<void> confirm(String token) => _guard(() async {
        await _dio.post('/portal/claim/confirm', options: PortalClient.auth(token));
      });

  /// TRUSTEE only, APPROVED only. First override wins; a repeat does not rewrite
  /// the attribution.
  Future<void> override(String token) => _guard(() async {
        await _dio.post('/portal/claim/override', options: PortalClient.auth(token));
      });

  /// TRUSTEE only. Accepts the trusteeship using this portal session as the proof — the
  /// sign-in code went to the same phone the /trustee/:id flow would have texted, so a
  /// second code from a years-old invitation link would be ceremony, not assurance.
  /// Idempotent; a repeat does not rewrite when they accepted.
  Future<void> acceptTrusteeship(String token) => _guard(() async {
        await _dio.post('/portal/trustee/accept', options: PortalClient.auth(token));
      });

  /// The released will. A 403 here is IDENTICAL for SUBMITTED, UNDER_REVIEW,
  /// APPROVED, REJECTED and a missing claim — never infer status from it; read
  /// [claim] instead.
  Future<PortalWill> will(String token) => _guard(() async {
        final res = await _dio.get('/portal/will', options: PortalClient.auth(token));
        return PortalWill.fromJson((res.data as Map).cast<String, dynamic>());
      });

  /// ALL the legacy videos on the released will, oldest first. A will with none
  /// answers `{"videos": []}` (200, not 404), so an empty list is the only
  /// "no video" signal. Replaces the removed singular GET /portal/will/video.
  Future<List<PortalVideo>> videos(String token) => _guard(() async {
        final res = await _dio.get('/portal/will/videos', options: PortalClient.auth(token));
        final list = ((res.data as Map).cast<String, dynamic>()['videos'] as List?) ?? const [];
        return list.map((e) => PortalVideo.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  /// The executed will as PDF bytes.
  ///
  /// This route shipped server-side in a31f9db ("serve the WHOLE released estate —
  /// assets, wishes, guardianship, PDF, all videos") and the client half did not, so the
  /// one artifact heirs exist to receive was the only thing they could not get.
  ///
  /// Bytes over Dio rather than opening the URL: the endpoint authenticates on the
  /// X-Claim-Token header, which a browser navigation cannot carry — and putting the
  /// token in a query string would write a live credential into history and server logs.
  Future<Uint8List> pdf(
    String token, {
    // Narrative by default (DECISIONS §29) — and nowhere more so than here: this is
    // the copy a bereaved family reads. "I declare that, as of the sealing of this
    // will…" is the register the moment calls for; the table is one query param away.
    String format = 'essay',
    String lang = 'en',
    String display = 'percent',
  }) =>
      _guard(() async {
        final res = await _dio.get<List<int>>(
          '/portal/will/pdf',
          queryParameters: {'format': format, 'lang': lang, 'display': display},
          options: PortalClient.auth(token).copyWith(responseType: ResponseType.bytes),
        );
        return Uint8List.fromList(res.data ?? const []);
      });

  /// Burns the token server-side, so signing out is a real revocation and not a
  /// client-side forget. It matters: the credential may be sitting in a shared
  /// family device's browser.
  Future<void> exit(String token) => _guard(() async {
        await _dio.post('/portal/exit', options: PortalClient.auth(token));
      });
}
