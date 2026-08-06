import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/auth/data/auth_api.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';

/// Signs in the way the app now does: password, then the mandatory second factor.
///
/// Login stopped returning a session directly when the second factor became mandatory
/// for every password sign-in. Tests that did `(await login(...)) as Authenticated` had
/// been written against the old shape and could only fail from that point on — the cast
/// is against a challenge object now, not a session.
///
/// The code is read back out of the dev outbox, which is the same place a developer
/// reads it: GET /dev/sms when the account has a phone, Mailhog when it does not. That
/// keeps the helper honest — it completes a REAL challenge rather than bypassing one,
/// so these tests still prove the second factor is wired end to end.
///
/// Requires the backend started with OTP_DEV_ECHO=true (and Mailhog on :8025 for
/// phoneless accounts).
Future<Authenticated> loginFully(
  Dio dio, {
  required String email,
  required String password,
}) async {
  final api = AuthApi(dio);
  final res = await api.login(email: email, password: password);
  if (res is Authenticated) return res; // passkey/social — no challenge to answer
  final challenge = res as MfaRequired;
  final code = challenge.via == OtpChannel.sms
      ? await _codeFromDevSms(dio)
      : await _codeFromMailhog(email);
  return api.verifyMfa(userId: challenge.userId, code: code);
}

/// Registers a throwaway account with everything signup now requires.
///
/// Phone and a structured address became mandatory at signup — the phone carries the login
/// second factor, the witness and trustee invitations and the death-claim lookup, and the
/// address decides jurisdiction and is printed into the will. Six integration files were
/// each calling register() with only email/password/region; rather than paste a plausible
/// address into all of them, they share this one. A US address on purpose: North America is
/// the target market, so it is the shape most worth exercising.
Future<Authenticated> registerTestUser(
  Dio dio, {
  required String email,
  required String password,
  String region = 'US',
  String? phone,
}) =>
    AuthApi(dio).register(
      email: email,
      password: password,
      region: region,
      // Unique per account by default: the server normalises to E.164 and the death-claim
      // lookup matches on it, so shared numbers across tests would collide.
      phone: phone ?? '+1415${(DateTime.now().microsecondsSinceEpoch % 10000000).toString().padLeft(7, '0')}',
      addressLine1: '1 Test Street',
      addressCity: 'Austin',
      addressArea: 'TX',
      addressPostalCode: '78701',
      addressCountry: 'US',
    );

/// Grants a throwaway account a comp tier, which SEALING now requires.
///
/// seal() enforces the paywall server-side (DECISIONS §25): a will cannot be executed
/// without an active plan. That is correct and deliberate, but it means a freshly
/// registered e2e account can no longer produce a SEALED will — and a sealed will is the
/// precondition for the whole death-claim and heir-portal half of the product. Driving a
/// real Stripe checkout here would need live keys and a webhook the suite cannot receive,
/// so the run takes the same shortcut an admin would: a comp.
///
/// `POST /dev/comp` exists only on a backend started with OTP_DEV_ECHO=true — the same
/// switch that exposes the SMS outbox this file already reads codes from.
Future<void> grantComp(Dio dio, String email, {String tier = 'ULTIMATE'}) async {
  try {
    await dio.post('/dev/comp', data: {'email': email, 'tier': tier});
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      fail('POST /dev/comp is not registered. Start the backend with OTP_DEV_ECHO=true — '
          'sealing requires an active plan, so this test cannot produce a sealed will without it.');
    }
    throw ApiException.fromDio(e);
  }
}

/// Confirms a freshly registered account's email, which sealing requires.
///
/// seal() refuses an unconfirmed address — the will names the address its witnesses,
/// trustee and heirs are contacted at, so an unreachable one makes an unexecutable
/// will. A test that registers and then seals has to walk the same step a real owner
/// does: open the link that landed in the inbox.
Future<void> confirmEmail(Dio dio, String email) async {
  final token = await _verifyTokenFromMailhog(email);
  await AuthApi(dio).verifyEmail(token);
}

/// Mailhog hands back the RAW MIME body, which for these mails is quoted-printable.
/// That matters here: QP escapes '=' as '=3D', so the verification link arrives as
/// `verify-email?token=3D<token>` and a naive match captures "3D…" — a token the server
/// rejects as invalid, which reads like a broken verifier rather than a broken test.
String _decodeQuotedPrintable(String s) => s
    .replaceAll('=\r\n', '') // soft line breaks (QP wraps at 76 chars)
    .replaceAll('=\n', '')
    .replaceAllMapped(
      RegExp(r'=([0-9A-Fa-f]{2})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );

Future<String> _verifyTokenFromMailhog(String email) async {
  final mailhog = Dio(BaseOptions(baseUrl: 'http://localhost:8025'));
  final re = RegExp(r'verify-email\?token=([A-Za-z0-9_-]+)');
  for (var attempt = 0; attempt < 20; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final res = await mailhog.get<Map<String, dynamic>>(
      '/api/v2/search',
      queryParameters: {'kind': 'to', 'query': email},
    );
    for (final item in (res.data?['items'] as List?) ?? const []) {
      final body = ((item as Map)['Content'] as Map)['Body'] as String? ?? '';
      final m = re.firstMatch(_decodeQuotedPrintable(body));
      if (m != null) return m.group(1)!;
    }
  }
  fail('No verification mail reached Mailhog for $email — is Mailhog running on :8025?');
}

/// The newest 6-digit code in the dev SMS outbox. Exposed because codes now reach accounts
/// by SMS rather than email in most flows: a phone is mandatory at signup, so an
/// email+password account always has one, and the OTP channel prefers it.
Future<String> latestDevSmsCode(Dio dio) => _codeFromDevSms(dio);

final _codeRe = RegExp(r'verification code is (\d{6})');

/// The dev SMS outbox is newest-FIRST, so the live code is the first match, not the
/// last. Reading from the wrong end hands back an expired code from an earlier run.
Future<String> _codeFromDevSms(Dio dio) async {
  final probe = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
  for (var attempt = 0; attempt < 20; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final res = await probe.get<List<dynamic>>('/dev/sms');
    for (final row in res.data ?? const []) {
      final m = _codeRe.firstMatch((row as Map)['body'] as String? ?? '');
      if (m != null) return m.group(1)!;
    }
  }
  fail('No login code appeared at GET /dev/sms — start the backend with OTP_DEV_ECHO=true.');
}

Future<String> _codeFromMailhog(String email) async {
  final mailhog = Dio(BaseOptions(baseUrl: 'http://localhost:8025'));
  for (var attempt = 0; attempt < 20; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final res = await mailhog.get<Map<String, dynamic>>(
      '/api/v2/search',
      queryParameters: {'kind': 'to', 'query': email},
    );
    // Mailhog returns newest first too; take the first message that carries a code.
    for (final item in (res.data?['items'] as List?) ?? const []) {
      final body = ((item as Map)['Content'] as Map)['Body'] as String? ?? '';
      final m = _codeRe.firstMatch(body);
      if (m != null) return m.group(1)!;
    }
  }
  fail('No login code reached Mailhog for $email — is Mailhog running on :8025?');
}
