import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../../../core/utils/base64url.dart';
import '../domain/passkey_exceptions.dart';

/// Web: the real WebAuthn ceremonies, via `package:web` + `dart:js_interop`.
///
/// `package:web` over a dedicated passkeys package because it is ALREADY a
/// direct dependency (blob-URL revocation) and its 1.1.x bindings cover the
/// whole WebAuthn surface — one less supply-chain item for an app that holds
/// wills. The browser's own JSON bridges (`PublicKeyCredential.toJSON()`,
/// `parseCreationOptionsFromJSON()`) are deliberately NOT used: Safari gained
/// them late, so this file converts base64url <-> ArrayBuffer itself through
/// the unit-tested codec in core/utils/base64url.dart.
///
/// Both ceremonies take the server's `options` JSON exactly as issued
/// (PublicKeyCredential*OptionsJSON) and return the response JSON shape that
/// @simplewebauthn/server's verify functions expect.

/// WebAuthn needs both the API and a secure context (https or localhost) —
/// feature-detected, not user-agent-sniffed.
bool get webAuthnSupported =>
    web.window.isSecureContext && web.window.has('PublicKeyCredential');

/// Registration: `navigator.credentials.create()`.
///
/// [options] is PublicKeyCredentialCreationOptionsJSON from
/// POST /auth/passkeys/register/options. Returns RegistrationResponseJSON for
/// the `response` field of POST /auth/passkeys/register/verify.
Future<Map<String, dynamic>> createPasskeyCredential(Map<String, dynamic> options) async {
  final publicKey = Map<String, dynamic>.from(options);
  publicKey['challenge'] = base64UrlDecode(options['challenge'] as String);
  final user = Map<String, dynamic>.from(options['user'] as Map);
  user['id'] = base64UrlDecode(user['id'] as String);
  publicKey['user'] = user;
  final exclude = options['excludeCredentials'];
  if (exclude is List) publicKey['excludeCredentials'] = _decodeDescriptorIds(exclude);

  final credential = await _ceremony(
    () => web.window.navigator.credentials
        .create({'publicKey': publicKey}.jsify() as web.CredentialCreationOptions)
        .toDart,
    registering: true,
  );

  final response = credential.response as web.AuthenticatorAttestationResponse;
  return {
    ..._credentialEnvelope(credential),
    'response': {
      'clientDataJSON': base64UrlEncodeNoPad(response.clientDataJSON.toDart.asUint8List()),
      'attestationObject': base64UrlEncodeNoPad(response.attestationObject.toDart.asUint8List()),
      'transports': _transports(response),
    },
  };
}

/// Authentication: `navigator.credentials.get()`.
///
/// [options] is PublicKeyCredentialRequestOptionsJSON from
/// POST /auth/passkeys/login/options. Returns AuthenticationResponseJSON for
/// the `response` field of POST /auth/passkeys/login/verify.
Future<Map<String, dynamic>> getPasskeyAssertion(Map<String, dynamic> options) async {
  final publicKey = Map<String, dynamic>.from(options);
  publicKey['challenge'] = base64UrlDecode(options['challenge'] as String);
  final allow = options['allowCredentials'];
  if (allow is List) publicKey['allowCredentials'] = _decodeDescriptorIds(allow);

  final credential = await _ceremony(
    () => web.window.navigator.credentials
        .get({'publicKey': publicKey}.jsify() as web.CredentialRequestOptions)
        .toDart,
    registering: false,
  );

  final response = credential.response as web.AuthenticatorAssertionResponse;
  final userHandle = response.userHandle;
  return {
    ..._credentialEnvelope(credential),
    'response': {
      'clientDataJSON': base64UrlEncodeNoPad(response.clientDataJSON.toDart.asUint8List()),
      'authenticatorData': base64UrlEncodeNoPad(response.authenticatorData.toDart.asUint8List()),
      'signature': base64UrlEncodeNoPad(response.signature.toDart.asUint8List()),
      if (userHandle != null) 'userHandle': base64UrlEncodeNoPad(userHandle.toDart.asUint8List()),
    },
  };
}

/// The fields shared by both response shapes. `credential.id` is the browser's
/// own base64url of rawId — passed through untouched, because the backend looks
/// the credential up by this exact string.
Map<String, dynamic> _credentialEnvelope(web.PublicKeyCredential credential) => {
      'id': credential.id,
      'rawId': base64UrlEncodeNoPad(credential.rawId.toDart.asUint8List()),
      'type': credential.type,
      if (credential.authenticatorAttachment != null)
        'authenticatorAttachment': credential.authenticatorAttachment,
      'clientExtensionResults': _clientExtensionResults(credential),
    };

/// Descriptor lists (excludeCredentials / allowCredentials): only `id` is
/// binary; `type` and `transports` pass through.
List<Map<String, dynamic>> _decodeDescriptorIds(List raw) => [
      for (final d in raw)
        {
          ...Map<String, dynamic>.from(d as Map),
          'id': base64UrlDecode(d['id'] as String),
        },
    ];

/// Runs one browser ceremony, mapping the DOMException taxonomy onto the app's
/// typed [PasskeyException]s (same catch pattern as camera_web).
Future<web.PublicKeyCredential> _ceremony(
  Future<web.Credential?> Function() run, {
  required bool registering,
}) async {
  web.Credential? credential;
  try {
    credential = await run();
  } on web.DOMException catch (e) {
    switch (e.name) {
      // The user dismissed the prompt, it timed out, or no usable passkey
      // exists here — one error by spec, so sites cannot probe for credentials.
      case 'NotAllowedError':
      case 'AbortError':
        throw const PasskeyCancelled();
      // create(): this authenticator already holds a passkey for this account.
      case 'InvalidStateError' when registering:
        throw const PasskeyAlreadyRegistered();
      case 'NotSupportedError':
        throw const PasskeyUnsupported();
      default:
        // Includes SecurityError — an rpId/origin misconfiguration, our bug.
        throw PasskeyFailed('${e.name}: ${e.message}');
    }
  }
  if (credential == null) throw const PasskeyFailed('ceremony returned no credential');
  return credential as web.PublicKeyCredential;
}

/// `getTransports()` is missing on older engines; absence is data the server
/// can live without, not an error.
List<String> _transports(web.AuthenticatorAttestationResponse response) {
  try {
    return response.getTransports().toDart.map((t) => t.toDart).toList();
  } catch (_) {
    return const [];
  }
}

/// Extension outputs (e.g. credProps) — round-tripped through jsonEncode so the
/// map is guaranteed JSON-safe for the wire; `{}` is a valid value if anything
/// resists conversion.
Map<String, dynamic> _clientExtensionResults(web.PublicKeyCredential credential) {
  try {
    final safe = jsonDecode(jsonEncode(credential.getClientExtensionResults().dartify()));
    if (safe is Map) return safe.cast<String, dynamic>();
  } catch (_) {/* fall through */}
  return {};
}
