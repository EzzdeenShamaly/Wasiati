# Google Sign-In — per-platform setup

Wired in code and live on the login and signup screens. The button **only renders where it
can actually complete** (`Env.googleSignInAvailable`), so an unconfigured platform shows no
button rather than one that fails.

Why it matters beyond convenience: an OAuth login is **exempt from the login OTP**
(`auth.service.ts` `loginWithOAuth`), while a password login always sends one. So every
account that signs in this way costs **nothing** per sign-in instead of a message — and at
Saudi rates a message is $0.1949.

## What the app reads

Both are `--dart-define`, and both may be absent (the button then hides):

| Define | Used by |
|---|---|
| `GOOGLE_CLIENT_ID_WEB` | Web (as the client id) **and** Android/iOS (as `serverClientId`, which is what makes the id_token carry an audience the backend accepts) |
| `GOOGLE_CLIENT_ID_IOS` | iOS only — its own OAuth client |

The backend accepts a comma-separated `GOOGLE_CLIENT_IDS`; every client id whose tokens
should be trusted must appear there.

## Web — working

Nothing further needed beyond the define. Verified: a production `flutter build web` with
`GOOGLE_CLIENT_ID_WEB` set compiles and the button renders.

Two real constraints, both confirmed against `google_sign_in_web` 0.12.4 source rather than
assumed:
- The constructor `clientId` **is** honoured (`params.clientId ?? autoDetectedClientId`), so
  the `<meta name="google-signin-client_id">` tag in `index.html` is a fallback, not a
  requirement. Nothing to add to `web/index.html`.
- `serverClientId` is **rejected on web** by `assert(params.serverClientId == null)`. It is
  therefore passed on native only. Worth knowing: asserts are stripped in release, so
  getting this wrong fails in debug and silently "works" in release — which reads as a
  browser-specific bug rather than a config error.
- **Authorised JavaScript origins** must list every origin the app is served from, in the
  Google Cloud credentials page: `https://app.wasiati.com` for production, and for local
  work `http://localhost` plus the exact dev port.

## Android — code ready, needs a fingerprint

No client id goes in the bundle; Android is identified by its **SHA-1 signing fingerprint**.

1. Get the fingerprints — debug and release are different keys, so register both:
   `keytool -list -v -keystore <keystore> -alias <alias>`
2. In Google Cloud → Credentials, create an **Android** OAuth client with the package name
   and each SHA-1.
3. Build with `GOOGLE_CLIENT_ID_WEB` defined; `serverClientId` is what yields the id_token.

Until the fingerprint is registered, sign-in fails at the Google sheet rather than in our
code. NOT BUILT HERE: this machine has no Android SDK (`flutter doctor` reports the
toolchain missing), so the Android build is unverified — only the Dart compiles.

## iOS — code ready, needs a client id and a URL scheme

1. Create an **iOS** OAuth client in Google Cloud; note its client id and the
   **reversed** client id.
2. Pass it as `GOOGLE_CLIENT_ID_IOS`.
3. Add the reversed client id as a URL scheme in `ios/Runner/Info.plist`, or the sign-in
   sheet cannot hand control back to the app:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.YOUR-REVERSED-CLIENT-ID</string>
    </array>
  </dict>
</array>
```

The button stays hidden on iOS until `GOOGLE_CLIENT_ID_IOS` is set, because without the
scheme the sheet opens and never returns. NOT BUILT HERE: an iOS build needs macOS.

## Apple Sign-In — still not wired

Deliberately unchanged. It needs the **Apple Developer Program ($99/yr)** and an SDK that is
not a dependency, so its button keeps the honest "coming soon". Note the App Store
requirement: an app offering other social logins must also offer Sign in with Apple, so this
is a gate on the iOS release, not an optional extra.
