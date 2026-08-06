import 'package:dio/dio.dart';
import '../../../core/network/api_exception.dart';
import '../domain/death_claim_models.dart';

class DeathClaimsApi {
  final Dio _dio;
  DeathClaimsApi(this._dio);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// THE way in. A grieving family has no account, no will id and no link — only the
  /// deceased's contact details and their own.
  ///
  /// Returns nothing, and that is the entire design. The response is 202 with an
  /// identical body in every case: no such person, a person with no sealed will, a
  /// person found but the caller is not named on their will, and a full match. The
  /// caller cannot tell which happened, so this endpoint cannot be used to discover
  /// whether someone is dead, holds a will, or has a given person attached to it.
  ///
  /// TWO fields, deliberately. With only the deceased's contact, one request would fan
  /// a message out to every witness, trustee and heir on the will — a harassment
  /// amplifier that also leaks "this person is claimable". Requiring the claimant's own
  /// contact means an attacker must already know both sides, and can only reach the one
  /// party they named.
  ///
  /// When both sides match, the link is sent to the contact ALREADY ON FILE for that
  /// party — never to whatever was typed here.
  Future<void> lookup({required String deceasedContact, required String claimantContact}) =>
      _guard(() => _dio.post('/death-claims/lookup', data: {
            'deceasedContact': deceasedContact,
            'claimantContact': claimantContact,
          }));

  /// Files the claim using the single-use token from the lookup link.
  ///
  /// No will id, no phone and no role: all three come out of the token server-side and
  /// cannot be influenced from here. Replaces the old
  /// `POST /wills/:willId/death-claims`, which took a will id no grieving family could
  /// know and answered with three distinguishable errors that let anyone holding a will
  /// id enumerate the people attached to it.
  Future<void> submit({
    required String claimToken,
    required String submittedByName,
    required String certificateFileId,
  }) =>
      _guard(() => _dio.post(
            '/claim/submit',
            data: {'submittedByName': submittedByName, 'certificateFileId': certificateFileId},
            // Its own header, never Authorization: a claim token and a JWT are different
            // credentials and no route should accept whichever it happens to find.
            options: Options(headers: {'X-Claim-Token': claimToken}),
          ));

  Future<List<DeathClaim>> pending() => _guard(() async {
        final res = await _dio.get('/admin/death-claims/pending');
        return (res.data as List).map((e) => DeathClaim.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  /// A short-lived link to the death certificate this claim was filed on.
  ///
  /// The claim also carries a `certificateFileUrl`, and that field is NOT usable: it points
  /// at the owner-scoped `/files/:id/download`, and the file belongs to the deceased, so no
  /// admin request can ever return it. This route exists because of that — it is the only
  /// way the reviewer sees the document they are approving.
  Future<String> certificateUrl(String id) => _guard(() async {
        final res = await _dio.get('/admin/death-claims/$id/certificate');
        return ((res.data as Map).cast<String, dynamic>())['url'] as String;
      });

  Future<void> underReview(String id) => _guard(() => _dio.post('/admin/death-claims/$id/under-review'));
  Future<void> approve(String id) => _guard(() => _dio.post('/admin/death-claims/$id/approve'));
  Future<void> reject(String id, String reason) => _guard(() => _dio.post('/admin/death-claims/$id/reject', data: {'reason': reason}));
  Future<void> release(String id) => _guard(() => _dio.post('/admin/death-claims/$id/release'));
}
