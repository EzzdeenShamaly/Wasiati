import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '_integration_guard.dart';
import '_integration_login.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/death_claims/data/death_claims_api.dart';
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';

/// Reads the backend's dev SMS outbox for one destination.
///
/// The claim path never returns a code or a token in a response body: the lookup
/// endpoint is unauthenticated and must look identical for every input, so anything it
/// handed back would be both a consumable credential for an anonymous caller and a
/// yes/no oracle for "is this person claimable?". Codes and links go out over SMS only,
/// and this e2e run reads them the way the real family does — off the handset.
/// `GET /dev/sms` is that handset, and exists only on a backend started with
/// OTP_DEV_ECHO=true.
Future<List<String>> _devSmsBodies(Dio dio, String destination) async {
  final Response<dynamic> res;
  try {
    res = await dio.get('/dev/sms', queryParameters: {'destination': destination});
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      fail('GET /dev/sms is not registered. Start the backend with OTP_DEV_ECHO=true — '
          'the claim link goes out over SMS only and cannot be read any other way.');
    }
    throw ApiException.fromDio(e);
  }
  return (res.data as List).map((m) => (m as Map)['body'] as String).toList();
}

String? _codeFrom(List<String> bodies) =>
    bodies.isEmpty ? null : RegExp(r'\b(\d{6})\b').firstMatch(bodies.first)?.group(1);

/// The claim link is `<base>/claim/<token>`; the token is base64url.
String? _claimTokenFrom(List<String> bodies) {
  for (final b in bodies) {
    final m = RegExp(r'/claim/([A-Za-z0-9_-]{20,})').firstMatch(b);
    if (m != null) return m.group(1);
  }
  return null;
}

/// Drives THE WAY IN: `POST /death-claims/lookup`.
///
/// This file used to walk `POST /wills/:willId/death-claims/request` then
/// `POST /wills/:willId/death-claims`. Both routes are DELETED. They required a will
/// id — a UUID no grieving family member can possibly know — so in practice a claim
/// could not be started at all; and they answered with three distinguishable errors
/// (unknown will / known will but unauthorised phone / authorised but no pending code),
/// which made anyone holding a will id able to enumerate the people attached to it.
///
/// What is asserted here is the property that replaced them: the lookup is CONSTANT.
/// A matching pair and a bogus one produce the same status and the same body, and the
/// only observable difference is out-of-band — a link reaches the roster's phone in the
/// matching case and nothing is sent in the others.
void main() {
  test('lookup: a matching pair gets a link out-of-band, a bogus one is indistinguishable', () async {
    final base = 'http://localhost:4000';
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final ownerEmail = 'dc_$stamp@wasiati.test';
    // UNIQUE per run, like the email. These were fixed constants, which collided with the
    // per-destination rate limit the lookup enforces (3/hour, 10/day, keyed on the
    // destination hash): the first few runs delivered, and every run after that silently
    // got no SMS and failed at "must deliver a claim link" — looking exactly like a broken
    // lookup rather than an exhausted test fixture. A unique number per run keeps each run
    // independent, and is closer to reality anyway.
    final suffix = (stamp % 10000000).toString().padLeft(7, '0');
    final witnessPhone = '+1415$suffix';
    final witnessTwoPhone = '+1416$suffix';

    final userDio = Dio(BaseOptions(baseUrl: base, headers: {'X-Client-Platform': 'ios'}, contentType: Headers.jsonContentType));
    final anonDio = Dio(BaseOptions(baseUrl: base, headers: {'X-Client-Platform': 'ios'}, contentType: Headers.jsonContentType));

    try {
      // --- an executed will, because lookup only ever considers SEALED wills ---
      final reg = await registerTestUser(userDio, email: ownerEmail, password: 'DcPass123456');
      userDio.options.headers['Authorization'] = 'Bearer ${reg.accessToken}';
      // Sealing refuses an unconfirmed address, so open the link like a real owner does.
      await confirmEmail(userDio, ownerEmail);
      // ...and refuses an account with no plan (the paywall is enforced server-side, not
      // just in the UI). A real owner has paid by this point; the run takes a comp.
      await grantComp(userDio, ownerEmail);
      final wills = WillsApi(userDio);
      final willId = (await wills.create(tier: 'STANDARD', heirs: const [Heir(HeirRelation.wife, 'Aisha')])).id;

      // Witnesses BEFORE the owner signs. assertWitnessQuorum refuses to sign a will with
      // fewer than the required witnesses attached, because signing sets locked=true and a
      // will signed with none could never reach WITNESSED — stranded, uneditable and
      // unsealable. This test had the two steps the other way round and so failed on its
      // first real run against a live backend, having only ever skipped before.
      for (final (name, phone) in [('Witness One', witnessPhone), ('Witness Two', witnessTwoPhone)]) {
        await wills.addWitness(willId, fullName: name, phone: phone);
      }

      // A CONFIRMED trustee, with an email: seal() now refuses a will release()
      // could never complete (no confirmed trustee) and one that could be released
      // to nobody (no address anywhere on the roster). This fixture is a real
      // executed will, so it satisfies both the way a real owner does.
      final trusteePhone = '+1417$suffix';
      await wills.addTrustee(willId,
          fullName: 'Tariq Trustee', phone: trusteePhone, email: 'dc_trustee_$stamp@wasiati.test');
      final trusteeId = (await wills.trustees(willId)).first.id;
      await wills.sendTrusteeCode(trusteeId);
      final trusteeCode = _codeFrom(await _devSmsBodies(userDio, trusteePhone));
      expect(trusteeCode, isNotNull, reason: 'no trustee code reached the dev outbox for $trusteePhone');
      await userDio.post('/trustees/$trusteeId/confirm', data: {'code': trusteeCode});

      await wills.sign(willId, signatureData: 'data:image/png;base64,AAAA');

      // Each witness signs with a code read off the handset (the dev SMS outbox).
      for (final w in await wills.witnesses(willId)) {
        await wills.sendWitnessCode(w.id);
        final code = _codeFrom(await _devSmsBodies(userDio, w.phone));
        expect(code, isNotNull, reason: 'no signing code reached the dev outbox for ${w.phone}');
        await userDio.post('/witnesses/${w.id}/confirm', data: {
          'code': code,
          'signatureData': 'data:image/png;base64,AAAA',
          'legalName': w.fullName,
        });
      }
      await wills.seal(willId);

      final claims = DeathClaimsApi(anonDio);

      // --- CASE 1: both sides match. 202, and a link lands on the ROSTER's phone. ---
      await claims.lookup(deceasedContact: ownerEmail, claimantContact: witnessPhone);
      final token = _claimTokenFrom(await _devSmsBodies(userDio, witnessPhone));
      expect(token, isNotNull,
          reason: 'a matching lookup must deliver a claim link to the witness phone on file');

      // --- CASE 2: the deceased does not exist. Must be indistinguishable. ---
      final before = (await _devSmsBodies(userDio, witnessPhone)).length;
      await claims.lookup(
        deceasedContact: 'nobody_$stamp@wasiati.test',
        claimantContact: witnessPhone,
      );
      expect((await _devSmsBodies(userDio, witnessPhone)).length, before,
          reason: 'a lookup against an unknown person must send nothing');

      // --- CASE 3: the deceased exists, but the claimant is not on the will. ---
      await claims.lookup(deceasedContact: ownerEmail, claimantContact: '+15550009999');
      expect((await _devSmsBodies(userDio, witnessPhone)).length, before,
          reason: 'a lookup from a stranger must send nothing to the real witness');

      // All three returned without throwing, which is the constant-response property as
      // the client observes it: every non-2xx would have surfaced as an ApiException.
      // The byte-for-byte body and status comparison lives in the backend unit test
      // (claim-lookup.spec.ts), where all four cases can be driven deterministically.

      // --- the national spelling of the SAME number must match too ---
      // The bug this whole path existed to fix: 0-prefixed local numbers never matched
      // the +1/+966 form on file, so a real family's first attempt was always rejected.
      final beforeLocal = (await _devSmsBodies(userDio, witnessPhone)).length;
      // The same line in national form: drop the +1 country code the will has on file.
      await claims.lookup(deceasedContact: ownerEmail, claimantContact: '415$suffix');
      expect((await _devSmsBodies(userDio, witnessPhone)).length, greaterThan(beforeLocal),
          reason: 'a nationally-formatted phone must match the E.164 number on the will');
    } on ApiException catch (e) {
      // Skip ONLY when the environment is at fault: no HTTP response at all (backend
      // down) or the throttler pushing back. Anything else is a real regression — a
      // blanket skip here is what let the de-echoed OTP endpoint break this silently.
      if (e.statusCode == null || e.statusCode == 429) {
        skipIfBackendDown(e);
        return;
      }
      rethrow;
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
