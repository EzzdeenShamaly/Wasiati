import 'auth_models.dart';

/// App-wide authentication state (Dart 3 sealed union — exhaustively matchable).
sealed class AuthState {
  const AuthState();
}

/// Boot: probing for a resumable session.
class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

/// Password verified; awaiting the one-time code. [via] is which channel it went
/// out on (SMS when the account has a phone, otherwise email), so the prompt can
/// tell the user where to actually look.
class AuthAwaitingMfa extends AuthState {
  final String userId;
  final OtpChannel via;
  /// Opaque proof of the password step; the only credential the resend endpoint takes.
  final String challengeToken;
  const AuthAwaitingMfa(this.userId, this.via, this.challengeToken);
}

class AuthSignedIn extends AuthState {
  final AuthUser user;
  const AuthSignedIn(this.user);
}
