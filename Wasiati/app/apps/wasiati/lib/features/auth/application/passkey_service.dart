import '../data/auth_api.dart';
// The repo's conditional-import pattern (blob_url_web/stub): the web file runs
// the real browser ceremonies; the stub keeps non-web builds compiling and
// reports unsupported instead of silently doing nothing.
import '../data/webauthn_ceremony_stub.dart'
    if (dart.library.html) '../data/webauthn_ceremony_web.dart' as ceremony;
import '../domain/auth_models.dart';
import '../domain/passkey_exceptions.dart';

/// One WebAuthn ceremony step: server-issued options in, browser response out.
typedef PasskeyCeremony = Future<Map<String, dynamic>> Function(Map<String, dynamic> options);

/// Drives the two passkey flows end to end against the backend:
///
///   sign-in : POST login/options    -> navigator.credentials.get()    -> POST login/verify
///   register: POST register/options -> navigator.credentials.create() -> POST register/verify
///
/// Each options call returns `{ options, sessionId }`; the sessionId keys the
/// server-side challenge in Redis and MUST travel back with the browser's
/// response — that round trip is the whole ceremony.
///
/// Why this matters (owner decision f242634): a password login always requires
/// an OTP; a passkey is the one exempt path because it carries its own
/// possession proof. Registration from Settings is what makes sign-in possible
/// at all — without it nobody ever HAS a passkey.
///
/// The ceremony functions are injectable so VM tests can drive the full
/// options -> ceremony -> verify chain; production uses the conditional import.
class PasskeyService {
  final AuthApi _api;
  final bool _supported;
  final PasskeyCeremony _create;
  final PasskeyCeremony _getAssertion;

  PasskeyService(
    this._api, {
    bool? supported,
    PasskeyCeremony? create,
    PasskeyCeremony? getAssertion,
  })  : _supported = supported ?? ceremony.webAuthnSupported,
        _create = create ?? ceremony.createPasskeyCredential,
        _getAssertion = getAssertion ?? ceremony.getPasskeyAssertion;

  /// Whether this platform can run a ceremony at all (WebAuthn + secure context).
  bool get supported => _supported;

  /// Sign in with a passkey. Throws [PasskeyException]s for the browser-side
  /// outcomes and ApiException for server refusals; returns the session on success.
  Future<Authenticated> signIn() async {
    if (!_supported) throw const PasskeyUnsupported();
    final issued = await _api.passkeyLoginOptions();
    final assertion = await _getAssertion(issued.options);
    return _api.passkeyLoginVerify(sessionId: issued.sessionId, response: assertion);
  }

  /// Register a passkey for the signed-in user (Settings → Security).
  Future<void> register() async {
    if (!_supported) throw const PasskeyUnsupported();
    final issued = await _api.passkeyRegisterOptions();
    final attestation = await _create(issued.options);
    await _api.passkeyRegisterVerify(sessionId: issued.sessionId, response: attestation);
  }
}
