import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// Build-time configuration. The flavor and API base URL are supplied via
/// --dart-define so the same code targets dev/staging/prod and each region's
/// backend without code changes:
///   flutter run --dart-define=API_BASE_URL=http://localhost:4000 --dart-define=FLAVOR=dev
enum AppFlavor { dev, staging, prod }

abstract final class Env {
  static const String _flavorRaw = String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  static AppFlavor get flavor => switch (_flavorRaw) {
        'prod' => AppFlavor.prod,
        'staging' => AppFlavor.staging,
        _ => AppFlavor.dev,
      };

  static bool get isDev => flavor == AppFlavor.dev;

  /// The region this build talks to. Each region is a separate, data-resident
  /// deployment, so this is fixed at build time and matches the backend's REGION.
  /// Used pre-auth (e.g. the login screen) where no user region is known yet;
  /// after sign-in prefer the user's own region.
  static const String region = String.fromEnvironment('REGION', defaultValue: 'US');

  /// Nafath is Saudi Arabia's national identity service — offer it nowhere else.
  static bool get supportsNafath => region == 'KSA';

  /// Backend base URL. Defaults to the local dev backend; Android emulators reach
  /// the host machine via 10.0.2.2 rather than localhost.
  static String get apiBaseUrl {
    const fromDefine = String.fromEnvironment('API_BASE_URL');
    final url = fromDefine.isNotEmpty
        ? fromDefine
        : (!kIsWeb && Platform.isAndroid ? 'http://10.0.2.2:4000' : 'http://localhost:4000');
    return _requireHttpsOutsideDev(url, 'API_BASE_URL');
  }

  /// A staging/prod build must never talk to a REMOTE backend (or send checkout return
  /// links) over cleartext HTTP — a missing/typo'd --dart-define would otherwise ship a
  /// release pointed at plain HTTP over the network. Loopback (localhost/10.0.2.2) http
  /// is still allowed in any flavor: it never leaves the device, so it carries no
  /// cleartext-network risk, and it keeps local testing of the staging flavor working.
  static String _requireHttpsOutsideDev(String url, String name) {
    if (flavor == AppFlavor.dev || url.startsWith('https://')) return url;
    final host = Uri.tryParse(url)?.host ?? '';
    const loopback = {'localhost', '127.0.0.1', '10.0.2.2', '::1'};
    // NATIVE builds keep the exemption: loopback there is a deliberate choice for
    // exercising a staging flavor against a local backend, and it never leaves the device.
    // On WEB it is a trap instead of a convenience — the fallback when the define is
    // MISSING is itself 'localhost', so the guard that exists to catch a forgotten
    // --dart-define would never fire, and the deployed bundle would tell every visitor's
    // browser to call their own machine. On web, a missing define must fail loudly.
    if (!kIsWeb && loopback.contains(host)) return url;
    throw StateError('$name must be https:// for a remote host in ${flavor.name} builds (got "$url").');
  }

  // --- Google Sign-In -------------------------------------------------------
  //
  // Three platforms, three different requirements, one shared audience:
  //
  //  · The WEB client id is also the `serverClientId` on Android and iOS. That is what
  //    makes the returned id_token carry an audience the BACKEND accepts — without it
  //    google_sign_in returns a token minted for the mobile client, which
  //    GOOGLE_CLIENT_IDS would have to be widened to trust separately.
  //  · Android needs no id in code at all; it is identified by its SHA-1 signing
  //    fingerprint registered in the Google console.
  //  · iOS needs its OWN client id, plus the matching reversed-DNS URL scheme in
  //    Info.plist, or the sign-in sheet cannot hand control back to the app.
  //
  // Supplied by --dart-define so one codebase targets every platform, and every getter
  // is allowed to be EMPTY: [googleSignInAvailable] then hides the button rather than
  // offering one that cannot complete. A button that fails is worse than no button.
  static const String googleClientIdWeb = String.fromEnvironment('GOOGLE_CLIENT_ID_WEB');
  static const String googleClientIdIos = String.fromEnvironment('GOOGLE_CLIENT_ID_IOS');

  /// The audience the backend verifies against — the web client id, on NATIVE only.
  ///
  /// Must be null on web: google_sign_in_web carries
  /// `assert(params.serverClientId == null, 'serverClientId is not supported on Web.')`,
  /// so passing it throws in debug (and is silently ignored in release, where asserts are
  /// stripped — a difference that would have made this look like a browser-only bug).
  /// It is unnecessary there anyway: a web sign-in already mints its token for the web
  /// client id, which is exactly the audience the backend accepts.
  static String? get googleServerClientId {
    if (kIsWeb) return null;
    return googleClientIdWeb.isEmpty ? null : googleClientIdWeb;
  }

  /// The per-platform client id the SDK itself needs (Android supplies its own).
  static String? get googleClientId {
    if (kIsWeb) return googleClientIdWeb.isEmpty ? null : googleClientIdWeb;
    if (Platform.isIOS) return googleClientIdIos.isEmpty ? null : googleClientIdIos;
    return null; // Android: identified by signing fingerprint, not an id in the bundle.
  }

  /// Whether "Continue with Google" can actually complete on THIS platform.
  ///
  /// Web and Android need only the web client id (Android as serverClientId, its own
  /// identity coming from the fingerprint). iOS additionally needs its own client id, so
  /// the button stays hidden there until one is configured — the alternative is a sheet
  /// that opens and cannot return.
  static bool get googleSignInAvailable {
    if (googleClientIdWeb.isEmpty) return false;
    if (!kIsWeb && Platform.isIOS) return googleClientIdIos.isNotEmpty;
    return true;
  }

  /// Value for the X-Client-Platform header — drives cookie (web) vs body (mobile)
  /// refresh-token delivery on the backend.
  static String get clientPlatform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'web';
  }

  /// Web uses an httpOnly refresh cookie (JS can't read it); mobile persists the
  /// refresh token in secure storage.
  static bool get usesRefreshCookie => kIsWeb;

  /// Base URL the app is served from — used for hosted-checkout success/cancel
  /// return links. On mobile this should be a deep link (app-links) in prod.
  static String get appUrl {
    const fromDefine = String.fromEnvironment('APP_URL');
    final url = fromDefine.isNotEmpty ? fromDefine : (kIsWeb ? 'http://localhost:3000' : 'https://wasiati.com');
    return _requireHttpsOutsideDev(url, 'APP_URL');
  }

  static String get checkoutSuccessUrl => '$appUrl/dashboard?checkout=success';
  static String get checkoutCancelUrl => '$appUrl/pricing?checkout=cancel';
  static String get billingReturnUrl => '$appUrl/dashboard';

  /// Where the hosted "change card" page returns to. Billing, not Plans: the user
  /// started on the billing page and expects to land back there and see the new
  /// card — `checkoutCancelUrl` would strand them on the pricing grid. Same host,
  /// so the backend's PAYMENT_RETURN_HOSTS allowlist covers it unchanged.
  static String get cardChangeSuccessUrl => '$appUrl/billing?card=updated';
  static String get cardChangeCancelUrl => '$appUrl/billing';
}
