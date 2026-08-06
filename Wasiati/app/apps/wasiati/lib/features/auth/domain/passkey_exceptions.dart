/// Typed outcomes of a WebAuthn browser ceremony, so every screen can tell the
/// user WHAT happened — never a silent no-op, never one generic error for
/// distinct situations the user can actually act on.
///
/// Note the deliberate coarseness of [PasskeyCancelled]: the WebAuthn spec makes
/// the browser collapse "the user dismissed the prompt" and "no usable passkey
/// exists on this device" into a single NotAllowedError, precisely so a site
/// cannot probe for credentials. The sign-in copy therefore covers both.
sealed class PasskeyException implements Exception {
  const PasskeyException();
}

/// No WebAuthn here: a browser without the API, an insecure (http, non-localhost)
/// context, or a non-web build reaching the stub.
class PasskeyUnsupported extends PasskeyException {
  const PasskeyUnsupported();
}

/// The prompt was dismissed or timed out — or no passkey is available on this
/// device (indistinguishable by design; see above).
class PasskeyCancelled extends PasskeyException {
  const PasskeyCancelled();
}

/// `create()` refused because this authenticator already holds a passkey for
/// this account (InvalidStateError).
class PasskeyAlreadyRegistered extends PasskeyException {
  const PasskeyAlreadyRegistered();
}

/// Anything else — e.g. SecurityError (rpId/origin misconfiguration) or an
/// unexpected response shape. [detail] is for logs, not for the user.
class PasskeyFailed extends PasskeyException {
  final String detail;
  const PasskeyFailed(this.detail);

  @override
  String toString() => 'PasskeyFailed: $detail';
}
