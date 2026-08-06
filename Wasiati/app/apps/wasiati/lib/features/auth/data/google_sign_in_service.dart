import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/config/env.dart';

/// Thrown when the user backs out of the Google sheet. Not an error to shout about —
/// cancelling is a normal thing to do, and a red banner for it reads as a failure.
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();
}

/// Thrown when Google completed but handed back no id_token, which is the only thing the
/// backend can verify. Distinguished from a cancel because it means MISCONFIGURATION —
/// almost always a missing `serverClientId`, where the SDK returns an access token for the
/// mobile client and no id_token at all.
class GoogleSignInNoToken implements Exception {
  const GoogleSignInNoToken();
}

/// Runs the Google sign-in ceremony and returns the id_token for the backend to verify.
///
/// Deliberately thin: it obtains a token and nothing else. The backend verifies the
/// signature and decides who the user is — the client never sends an email or a name,
/// because a client-supplied identity is not an identity.
class GoogleSignInService {
  GoogleSignInService({GoogleSignIn? client})
      : _client = client ??
            GoogleSignIn(
              // Per-platform client id (null on Android, which uses its signing
              // fingerprint) and the WEB id as the audience the backend accepts.
              clientId: Env.googleClientId,
              serverClientId: Env.googleServerClientId,
              // `email` only. Asking for more would show the user a longer consent screen
              // for data this product has no use for.
              scopes: const ['email'],
            );

  final GoogleSignIn _client;

  /// Signs in and returns the id_token.
  ///
  /// Signs OUT first so the account chooser always appears. Without it the SDK silently
  /// reuses the last account, which on a shared device hands the wrong person's estate to
  /// whoever taps the button — and on a will platform the likeliest second user of a device
  /// is a family member.
  Future<String> idToken() async {
    // try/catch, not .catchError: signOut() returns Future<GoogleSignInAccount?>, so an
    // onError handler would have to produce an account — and there is nothing useful to
    // do with a failure here anyway. Not being signed in is the state we want.
    try {
      await _client.signOut();
    } catch (_) {
      // Already signed out, or no cached account. Either is fine.
    }
    final account = await _client.signIn();
    if (account == null) throw const GoogleSignInCancelled();
    final auth = await account.authentication;
    final token = auth.idToken;
    if (token == null || token.isEmpty) throw const GoogleSignInNoToken();
    return token;
  }

  /// Clears the cached Google account, so the next sign-in asks again. Called on logout.
  Future<void> signOut() async {
    try {
      await _client.signOut();
    } catch (_) {
      // Nothing to sign out of.
    }
  }
}
