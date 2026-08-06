import '../domain/passkey_exceptions.dart';

/// Non-web platforms: no WebAuthn ceremony is available. [webAuthnSupported]
/// is false so callers surface the "not supported" message up front; if a call
/// slips through anyway it throws — a passkey path must never silently no-op.
///
/// (Native passkeys on iOS/Android would be a platform-channel implementation,
/// not this stub — web is the shipping target today.)
bool get webAuthnSupported => false;

Future<Map<String, dynamic>> createPasskeyCredential(Map<String, dynamic> options) async =>
    throw const PasskeyUnsupported();

Future<Map<String, dynamic>> getPasskeyAssertion(Map<String, dynamic> options) async =>
    throw const PasskeyUnsupported();
