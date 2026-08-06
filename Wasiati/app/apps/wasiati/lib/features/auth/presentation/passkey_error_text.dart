import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../domain/passkey_exceptions.dart';

/// One user-facing sentence for every way a passkey ceremony can end badly —
/// shared by the login screen (sign-in) and Settings (registration) so the two
/// surfaces never drift. Every branch names a next step; none is a shrug.
///
/// [registering] picks the copy for [PasskeyCancelled]: during sign-in the
/// browser deliberately won't say whether the user cancelled or simply has no
/// passkey here, so that copy covers both; during registration the user is
/// signed in and a cancel is just a cancel.
String passkeyErrorMessage(AppLocalizations l, Object error, {bool registering = false}) =>
    switch (error) {
      PasskeyUnsupported() => l.passkeyErrorUnsupported,
      PasskeyCancelled() => registering ? l.passkeyErrorRegisterCancelled : l.passkeyErrorCancelled,
      PasskeyAlreadyRegistered() => l.passkeyErrorAlreadyRegistered,
      PasskeyFailed() => l.passkeyErrorGeneric,
      ApiException(:final message) => message,
      _ => l.passkeyErrorGeneric,
    };
