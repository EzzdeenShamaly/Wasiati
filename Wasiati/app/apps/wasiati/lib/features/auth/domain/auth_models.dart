/// The authenticated user as returned by the backend JWT payload / /users/me.
class AuthUser {
  final String id;
  final String email;
  final String region; // KSA | CA | US
  final String role; // USER | ADMIN

  /// Whether the address has been proven via the verification mail. Sealing a
  /// will REQUIRES this (fdb4c3e). Only /users/me carries the field — the
  /// login/register token payloads do not — so it defaults to true and screens
  /// that gate on it must read a FRESH /users/me, never this cached copy:
  /// asserting "unverified" off stale data would nag a verified user, while
  /// the backend still enforces the real gate either way.
  final bool emailVerified;

  /// Registered city and ISO-3166 country, for the will document's testator line
  /// ("of {name} — {city, country}"). Like [emailVerified], only /users/me carries
  /// them — the login/register token payloads do not — so both are null on a
  /// session resumed from a token, and the header simply omits the place then.
  final String? addressCity;
  final String? addressCountry;

  const AuthUser({
    required this.id,
    required this.email,
    required this.region,
    required this.role,
    this.emailVerified = true,
    this.addressCity,
    this.addressCountry,
  });

  bool get isAdmin => role == 'ADMIN';

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as String,
        email: j['email'] as String,
        region: (j['region'] ?? 'US') as String,
        role: (j['role'] ?? 'USER') as String,
        emailVerified: (j['emailVerified'] as bool?) ?? true,
        addressCity: j['addressCity'] as String?,
        addressCountry: j['addressCountry'] as String?,
      );
}

/// Which channel a one-time code went out on — the challenge's `via` field.
/// The backend sends it to the phone when the account has one, else the email.
enum OtpChannel {
  sms,
  email,

  /// An enrolled authenticator app. NOTHING was sent: the code is already on the
  /// user's device, rolling every 30 seconds. Distinguishing this matters because the
  /// two things the SMS/email copy does — "check your messages" and offering a resend —
  /// are both wrong here, and would leave someone waiting for a text that will never
  /// arrive while pressing a button that cannot help them.
  totp,

  /// WhatsApp. Saudi numbers are routed here because an SMS to +966 costs ~4x what the
  /// same message costs over WhatsApp. Named separately because "check WhatsApp" and
  /// "check your texts" send someone to two different apps, and the wrong one reads as a
  /// code that never arrived.
  whatsapp;

  /// Missing/unknown values fall back to [sms] (the historical copy) rather than
  /// failing the login flow against an older backend.
  static OtpChannel parse(Object? v) => switch (v) {
        'email' => OtpChannel.email,
        'totp' => OtpChannel.totp,
        'whatsapp' => OtpChannel.whatsapp,
        _ => OtpChannel.sms,
      };

  /// True when the code arrives out-of-band and there is nothing to re-send.
  bool get isSelfServed => this == OtpChannel.totp;
}

/// Outcome of a login/register call: either fully authenticated, or an MFA
/// challenge that must be completed with a one-time code.
sealed class AuthResult {}

class Authenticated extends AuthResult {
  final AuthUser user;
  final String accessToken;
  final String? refreshToken; // present on mobile; null on web (httpOnly cookie)
  Authenticated({required this.user, required this.accessToken, this.refreshToken});
}

class MfaRequired extends AuthResult {
  final String userId;

  /// Where the code actually went, so the prompt can say "we texted you" vs
  /// "we emailed you" — a phoneless user's code goes to their inbox, and telling
  /// them to check their texts sends them hunting for an SMS that never came.
  final OtpChannel via;

  /// Opaque proof that THIS caller just passed the password step, and the only thing
  /// POST /auth/login/resend-mfa accepts. It carries no user identifier of its own, so
  /// unlike a bare userId it cannot be guessed into someone else's challenge and used to
  /// pump SMS at their phone. Held in memory for the life of the challenge only — never
  /// persisted, never in a URL.
  final String challengeToken;

  MfaRequired(this.userId, this.via, this.challengeToken);
}
