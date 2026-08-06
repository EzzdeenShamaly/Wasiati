import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '_integration_guard.dart';
import '_integration_login.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/confirm/data/confirm_api.dart';
import 'package:wasiati/features/wills/data/wills_api.dart';
import 'package:wasiati/features/wills/domain/wills_models.dart';

/// Fishes the newest 6-digit code for [phone] out of the dev SMS outbox.
/// GET /dev/sms returns newest first; body: "Your Wasiati verification code is
/// 123456. It expires in 10 minutes."
Future<String> _codeFromOutbox(Dio dio, String phone) async {
  final res = await dio.get('/dev/sms', queryParameters: {'destination': phone});
  final body = ((res.data as List).first as Map)['body'] as String;
  final m = RegExp(r'code is (\d{6})').firstMatch(body);
  expect(m, isNotNull, reason: 'No verification code in the outbox for $phone: "$body"');
  return m!.group(1)!;
}

/// Owner adds a witness + trustee to a will; both should list as PENDING.
/// An ApiException from any call (backend down or 429 throttle) skips the test.
void main() {
  test('add witness + trustee to a will -> both PENDING', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:4000', headers: {'X-Client-Platform': 'ios'}, contentType: Headers.jsonContentType));
    try {
      final reg = await registerTestUser(dio,
          email: 'wt_${DateTime.now().microsecondsSinceEpoch}@wasiati.test', password: 'WtPass123456');
      dio.options.headers['Authorization'] = 'Bearer ${reg.accessToken}';

      final api = WillsApi(dio);
      final will = await api.create(tier: 'STANDARD', heirs: const [Heir(HeirRelation.wife, 'Aisha')]);

      await api.addWitness(will.id, fullName: 'Omar Ali', phone: '+15551230001');
      await api.addTrustee(will.id, fullName: 'Bilal Khan', phone: '+15551230002');

      final witnesses = await api.witnesses(will.id);
      final trustees = await api.trustees(will.id);

      expect(witnesses, hasLength(1));
      expect(witnesses.first.status, 'PENDING');
      expect(trustees, hasLength(1));
      expect(trustees.first.status, 'PENDING');
    } on ApiException catch (e) {
      skipIfBackendDown(e);
    }
  }, timeout: const Timeout(Duration(seconds: 25)));

  /// The whole point of the /trustee/:id and /witness/:id screens: the app's
  /// OWN client (ConfirmApi — the same class those screens call) drives the
  /// PUBLIC confirm endpoints end-to-end against the live backend, using the
  /// code from the dev SMS outbox exactly as a real trustee/witness uses the
  /// one from their phone. Asserts the roster rows actually flip state — the
  /// transition the release gate and the seal both depend on.
  test('trustee confirm + witness sign via the public endpoints -> CONFIRMED / SIGNED', () async {
    final dio = Dio(BaseOptions(
        baseUrl: 'http://localhost:4000',
        headers: {'X-Client-Platform': 'ios'},
        contentType: Headers.jsonContentType));
    // Unique per-run phone numbers, so the newest outbox message is ours.
    final seed = (DateTime.now().microsecondsSinceEpoch % 10000000).toString().padLeft(7, '0');
    final witnessPhone = '+1555$seed';
    final trusteePhone = '+1556$seed';
    try {
      final reg = await registerTestUser(dio,
          email: 'wtc_${DateTime.now().microsecondsSinceEpoch}@wasiati.test', password: 'WtPass123456');
      dio.options.headers['Authorization'] = 'Bearer ${reg.accessToken}';

      final api = WillsApi(dio);
      final will = await api.create(tier: 'STANDARD', heirs: const [Heir(HeirRelation.wife, 'Aisha')]);
      await api.addWitness(will.id, fullName: 'Waleed Witness', phone: witnessPhone);
      await api.addTrustee(will.id, fullName: 'Tariq Trustee', phone: trusteePhone);
      final witnessId = (await api.witnesses(will.id)).first.id;
      final trusteeId = (await api.trustees(will.id)).first.id;

      // From here on: the PUBLIC surface, no auth header — a fresh bare client,
      // exactly as the SMS-link screens run.
      final public = Dio(BaseOptions(
          baseUrl: 'http://localhost:4000',
          headers: {'X-Client-Platform': 'ios'},
          contentType: Headers.jsonContentType));
      final confirm = ConfirmApi(public);

      await confirm.sendTrusteeCode(trusteeId);
      await confirm.confirmTrustee(trusteeId, code: await _codeFromOutbox(dio, trusteePhone));

      await confirm.sendWitnessCode(witnessId);
      // The legal name must match the roster; the comparison is case- and
      // whitespace-insensitive server-side, which '  waleed WITNESS ' exercises.
      await confirm.confirmWitness(
        witnessId,
        code: await _codeFromOutbox(dio, witnessPhone),
        legalName: '  waleed WITNESS ',
      );

      expect((await api.trustees(will.id)).first.status, 'CONFIRMED');
      expect((await api.witnesses(will.id)).first.status, 'SIGNED');

      // And a wrong code is refused with the backend's single 400 message.
      await confirm.sendTrusteeCode(trusteeId);
      try {
        await confirm.confirmTrustee(trusteeId, code: '000000');
        fail('A wrong code must not confirm');
      } on ApiException catch (e) {
        expect(e.statusCode, 400);
      }
    } on ApiException catch (e) {
      skipIfBackendDown(e);
    }
  }, timeout: const Timeout(Duration(seconds: 40)));
}
