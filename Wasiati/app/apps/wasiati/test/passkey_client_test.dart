import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/core/network/api_exception.dart';
import 'package:wasiati/features/auth/application/passkey_service.dart';
import 'package:wasiati/features/auth/data/auth_api.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';
import 'package:wasiati/features/auth/domain/passkey_exceptions.dart';

/// The passkey client chain, minus only the browser prompt itself.
///
/// The house disease is a feature that is built, unit-tested and never actually
/// reaches its endpoint — so these tests pin the wire: AuthApi must POST the
/// real /auth/passkeys/* paths with the `{ sessionId, response }` envelope the
/// DTOs demand, and PasskeyService must echo the SERVER's sessionId from the
/// options call into the verify call (the sessionId keys the challenge in
/// Redis; drop or swap it and every ceremony dies with "challenge expired").

// ---------------------------------------------------------------- AuthApi wire

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.reply, {this.status = 200});
  final Map<String, dynamic> reply;
  final int status;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(reply), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

(AuthApi, _FakeAdapter) _api(Map<String, dynamic> reply, {int status = 200}) {
  final dio = Dio(BaseOptions(contentType: Headers.jsonContentType));
  final adapter = _FakeAdapter(reply, status: status);
  dio.httpClientAdapter = adapter;
  return (AuthApi(dio), adapter);
}

// ------------------------------------------------------- PasskeyService chain

class _RecordingAuthApi extends AuthApi {
  _RecordingAuthApi() : super(Dio());
  final calls = <String>[];
  final loginOptions = {'challenge': 'bG9naW4', 'rpId': 'wasiati.com', 'userVerification': 'preferred'};
  final registerOptions = {
    'challenge': 'cmVnaXN0ZXI',
    'rp': {'name': 'Wasiati', 'id': 'wasiati.com'},
    'user': {'id': 'dXNlci0x', 'name': 'a@b.test', 'displayName': 'a@b.test'},
  };
  String? loginVerifySessionId;
  Map<String, dynamic>? loginVerifyResponse;
  String? registerVerifySessionId;
  Map<String, dynamic>? registerVerifyResponse;

  @override
  Future<({String sessionId, Map<String, dynamic> options})> passkeyLoginOptions() async {
    calls.add('login/options');
    return (sessionId: 'sess-login', options: loginOptions);
  }

  @override
  Future<Authenticated> passkeyLoginVerify({required String sessionId, required Map<String, dynamic> response}) async {
    calls.add('login/verify');
    loginVerifySessionId = sessionId;
    loginVerifyResponse = response;
    return Authenticated(
      user: const AuthUser(id: 'u1', email: 'a@b.test', region: 'QA', role: 'USER'),
      accessToken: 'jwt-1',
    );
  }

  @override
  Future<({String sessionId, Map<String, dynamic> options})> passkeyRegisterOptions() async {
    calls.add('register/options');
    return (sessionId: 'sess-reg', options: registerOptions);
  }

  @override
  Future<void> passkeyRegisterVerify({required String sessionId, required Map<String, dynamic> response}) async {
    calls.add('register/verify');
    registerVerifySessionId = sessionId;
    registerVerifyResponse = response;
  }
}

void main() {
  group('AuthApi passkey endpoints (wire shape)', () {
    test('login options: POSTs /auth/passkeys/login/options and returns BOTH halves', () async {
      final (api, adapter) = _api({
        'options': {'challenge': 'YWJj', 'rpId': 'wasiati.com'},
        'sessionId': 's-1',
      });

      final issued = await api.passkeyLoginOptions();

      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.path, '/auth/passkeys/login/options');
      expect(issued.sessionId, 's-1', reason: 'losing the sessionId orphans the Redis challenge');
      expect(issued.options['challenge'], 'YWJj');
    });

    test('login verify: POSTs the { sessionId, response } envelope and parses the session', () async {
      final (api, adapter) = _api({
        'accessToken': 'jwt-9',
        'user': {'id': 'u1', 'email': 'a@b.test', 'region': 'QA', 'role': 'USER'},
      });

      final auth = await api.passkeyLoginVerify(
        sessionId: 's-1',
        response: {'id': 'cred-1', 'type': 'public-key'},
      );

      expect(adapter.requests.single.path, '/auth/passkeys/login/verify');
      final sent = adapter.requests.single.data as Map;
      expect(sent['sessionId'], 's-1');
      expect((sent['response'] as Map)['id'], 'cred-1');
      expect(auth.accessToken, 'jwt-9');
      expect(auth.user.email, 'a@b.test');
      expect(auth.refreshToken, isNull, reason: 'web: refresh lives in the httpOnly cookie');
    });

    test('register options + verify hit their own paths with the same envelope', () async {
      final (api1, a1) = _api({'options': {'challenge': 'YWJj'}, 'sessionId': 's-2'});
      final issued = await api1.passkeyRegisterOptions();
      expect(a1.requests.single.path, '/auth/passkeys/register/options');
      expect(issued.sessionId, 's-2');

      final (api2, a2) = _api({'verified': true});
      await api2.passkeyRegisterVerify(sessionId: 's-2', response: {'id': 'cred-2'});
      expect(a2.requests.single.path, '/auth/passkeys/register/verify');
      expect((a2.requests.single.data as Map)['sessionId'], 's-2');
    });

    test('surfaces the backend refusal (expired challenge) as a clean ApiException', () async {
      final (api, _) = _api(
        {'message': 'Passkey challenge expired or invalid. Please try again.', 'statusCode': 400},
        status: 400,
      );

      expect(
        () => api.passkeyLoginVerify(sessionId: 'dead', response: {}),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', contains('expired'))),
      );
    });
  });

  group('PasskeyService', () {
    test('sign-in: options -> browser -> verify, with the sessionId echoed intact', () async {
      final api = _RecordingAuthApi();
      Map<String, dynamic>? seenByBrowser;
      final service = PasskeyService(
        api,
        supported: true,
        getAssertion: (options) async {
          seenByBrowser = options;
          return {'id': 'cred-1', 'type': 'public-key', 'response': {'signature': 'c2ln'}};
        },
        create: (_) async => fail('sign-in must never run the create() ceremony'),
      );

      final auth = await service.signIn();

      expect(api.calls, ['login/options', 'login/verify'], reason: 'both ends of the ceremony must be hit, in order');
      expect(seenByBrowser, same(api.loginOptions), reason: 'the server options feed the browser untouched');
      expect(api.loginVerifySessionId, 'sess-login');
      expect(api.loginVerifyResponse?['id'], 'cred-1');
      expect(auth.accessToken, 'jwt-1');
    });

    test('register: options -> create() -> verify, same echo contract', () async {
      final api = _RecordingAuthApi();
      final service = PasskeyService(
        api,
        supported: true,
        create: (options) async {
          expect(options, same(api.registerOptions));
          return {'id': 'cred-new', 'type': 'public-key'};
        },
        getAssertion: (_) async => fail('register must never run the get() ceremony'),
      );

      await service.register();

      expect(api.calls, ['register/options', 'register/verify']);
      expect(api.registerVerifySessionId, 'sess-reg');
      expect(api.registerVerifyResponse?['id'], 'cred-new');
    });

    test('unsupported platform: throws BEFORE any network call — no orphaned challenges', () async {
      final api = _RecordingAuthApi();
      final service = PasskeyService(api, supported: false);

      await expectLater(service.signIn(), throwsA(isA<PasskeyUnsupported>()));
      await expectLater(service.register(), throwsA(isA<PasskeyUnsupported>()));
      expect(api.calls, isEmpty);
    });

    test('user cancels the prompt: PasskeyCancelled surfaces and verify is never called', () async {
      final api = _RecordingAuthApi();
      final service = PasskeyService(
        api,
        supported: true,
        getAssertion: (_) async => throw const PasskeyCancelled(),
      );

      await expectLater(service.signIn(), throwsA(isA<PasskeyCancelled>()));
      expect(api.calls, ['login/options'], reason: 'a cancelled ceremony must not POST a verify');
    });

    test('the stub path (this VM) reports unsupported rather than silently no-opping', () async {
      final service = PasskeyService(_RecordingAuthApi());
      expect(service.supported, isFalse, reason: 'VM tests resolve the conditional import to the stub');
      await expectLater(service.signIn(), throwsA(isA<PasskeyUnsupported>()));
    });
  });
}
