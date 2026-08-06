# Mobile release — runbook

How the iOS and Android companions get from this repo into TestFlight / Play, what is
already wired, and what only Raed can do because it needs his accounts, his Mac, or
both. Companion-app rule up front (DECISIONS §25): **payment stays on the web**. The
iOS app sells nothing, links to no checkout, and carries no purchase SDK — selling
in-app would trigger Apple's 15–30% cut. Any future change that adds StoreKit or a
"buy" button to the iOS build is a pricing decision, not a code decision.

## What is already wired (verified in this repo)

- `.github/workflows/mobile.yml` — Android `.aab` + `.apk` on every push to `app/**`
  (and manual dispatch), iOS unsigned archive on a macOS runner. Green **today**,
  with no secrets configured: Android falls back to debug signing with a loud
  `::notice::`, iOS builds `--no-codesign`. The moment the secrets below exist,
  the same workflow produces Play-uploadable bundles with no workflow change.
- `android/app/build.gradle.kts` reads `android/key.properties` (gitignored, see
  `android/key.properties.example`) for upload-key signing; without it, release
  builds are debug-signed on purpose — and say so: the build prints a WARNING
  whenever a release task runs on the fallback (debug builds stay quiet). Before
  this wiring, release builds were debug-signed **silently** (the stock Flutter
  template default).
- Permissions: `ios/Runner/Info.plist` has camera/microphone/speech usage strings;
  `AndroidManifest.xml` has INTERNET/CAMERA/RECORD_AUDIO plus the API-30+
  `<queries>` for speech recognition and TTS. Already fixed — do not redo.
- Versioning: both stores read `version:` from `app/apps/wasiati/pubspec.yaml`
  (`flutter.versionCode/versionName` on Android; `FLUTTER_BUILD_NAME/NUMBER` in the
  iOS plist). One line bumps both platforms.

## Version bump convention

`version: 1.0.0+1` = `<semver>+<build number>`.

- **Bump `+N` for every store upload**, even a metadata-only resubmission. Both
  stores refuse a reused build number; N is shared across iOS and Android and only
  ever goes up.
- **Bump the semver** when users should perceive a release (release notes exist).
- The bump is a normal commit (`Bump to 1.0.1+5 for store upload`) so tags/history
  say what shipped.

## Android — what Raed does (works on this PC or the Mac)

### 1. Generate the upload keystore (once, ~2 minutes)

Anywhere with a JDK (this PC has one; on the Mac use the JBR inside Android Studio
or `brew install openjdk`). Keep the keystore **outside** any git checkout:

```
keytool -genkey -v -keystore ~/upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

(Windows: `%USERPROFILE%\upload-keystore.jks`.) It will prompt for a store
password, a key password, and identity fields — the CN can simply be `Wasiati`.
Save both passwords in a password manager immediately. This is the **upload key**,
not the app signing key: with Play App Signing (the default — accept it), Google
holds the real signing key, and a lost upload key is recoverable through a Play
support reset. A lost self-managed signing key is not — do not opt out.

### 2. Local signing config

Copy `app/apps/wasiati/android/key.properties.example` to `key.properties` beside
it, fill in the real values. Verify locally:

```
cd app/apps/wasiati
flutter build appbundle --release \
  --dart-define=FLAVOR=prod --dart-define=REGION=US \
  --dart-define=API_BASE_URL=https://api.wasiati.com \
  --dart-define=APP_URL=https://app.wasiati.com \
  --dart-define=GOOGLE_CLIENT_ID_WEB=<web oauth client id>
```

The dart-defines are not optional decoration: a native release built without
`API_BASE_URL` points at loopback **without any error** (env.dart's carve-out), so
always build through this command or CI.

### 3. GitHub secrets (repo → Settings → Secrets and variables → Actions)

| Name | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the keystore file, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | store password from step 1 |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | key password from step 1 |

By CLI — Mac: `base64 -i ~/upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64`;
Windows PowerShell:
`[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\upload-keystore.jks")) | gh secret set ANDROID_KEYSTORE_BASE64`.
The other three: `gh secret set ANDROID_KEYSTORE_PASSWORD` etc. (interactive prompt —
keeps the value out of shell history). Also set the repo **variable**
`GOOGLE_CLIENT_ID_IOS` when the iOS OAuth client exists (variables, not secrets:
OAuth client ids ship inside the binary and are public by design).

### 4. Play Console (needs the $25 account)

1. play.google.com/console → create developer account ($25 one-time). Identity
   verification (government ID) can take days — start it early. **Account type
   matters:** personal accounts created since Nov 2023 must run a closed test with
   a minimum number of opted-in testers for 14 consecutive days before production
   access (the required count was 20 at policy launch; Google has since revised
   it — check the current number in the console). An organization account (SHAMS
   entity + D-U-N-S number) skips the tester gate but takes longer to verify.
2. Create app → "Wasiati" → App bundle from CI artifact (`android-release`) or the
   local build → internal testing track first.
3. Accept Play App Signing. Then copy **both** SHA-1s from Play Console → Setup →
   App signing (the upload key cert AND the app-signing key cert) into the Google
   Cloud OAuth credentials as Android client fingerprints — store-installed builds
   are re-signed by Google, so Google Sign-In breaks in production if only the
   upload-key SHA-1 is registered (see GOOGLE_SIGNIN_SETUP.md).

## iOS — what Raed does on the Mac (nothing here works elsewhere)

1. **Enroll**: developer.apple.com → Apple Developer Program, $99/yr. Individual
   enrollment is fastest (hours-to-days); enrolling the SHAMS entity as an
   organization needs a D-U-N-S number and shows the company as seller. Decide
   which name should appear on the store before enrolling.
2. **Machine setup**: Xcode from the App Store, `sudo xcodebuild -runFirstLaunch`,
   CocoaPods (`sudo gem install cocoapods`), Flutter, clone, `flutter pub get` in
   `app/apps/wasiati`. There is no Podfile in the repo yet — the first iOS build
   generates it; commit it (and `Podfile.lock`) when it appears.
3. **Signing**: `open ios/Runner.xcworkspace` → Runner target → Signing &
   Capabilities → check "Automatically manage signing", pick the team. Bundle id
   `com.wasiati.wasiati` is already set; Xcode registers it and mints certs and
   profiles itself. No manual certificate work.
4. **App Store Connect**: appstoreconnect.apple.com → My Apps → "+" → New App →
   name Wasiati, bundle id from the dropdown, any internal SKU.
5. **Build and upload**:

   ```
   flutter build ipa --release \
     --dart-define=FLAVOR=prod --dart-define=REGION=US \
     --dart-define=API_BASE_URL=https://api.wasiati.com \
     --dart-define=APP_URL=https://app.wasiati.com \
     --dart-define=GOOGLE_CLIENT_ID_WEB=<web oauth client id> \
     --dart-define=GOOGLE_CLIENT_ID_IOS=<ios oauth client id>
   ```

   Upload the `.ipa` from `build/ios/ipa/` with the free **Transporter** app (Mac App
   Store), or archive via Xcode → Product → Archive → Distribute. TestFlight
   first; it appears in App Store Connect a few minutes after upload.
6. **CI signing later (optional)**: once certs exist, the mobile.yml iOS job can be
   upgraded to produce signed ipas (export the distribution cert as .p12 +
   provisioning profile into secrets, or Fastlane match). Not before — there is
   nothing to sign with today.

## What CAN vs CANNOT be verified without Raed's accounts

**Found by actually building (5 Aug 2026):** the Android app had NEVER been
buildable — the first real `flutter build apk` on this repo hit three pre-existing
defects, each fixed on this branch with a comment at the fix site: minSdk 21 vs
flutter_tts's declared 24 (manifest merger failure); the template's Kotlin 1.8.22
vs the 2.2-metadata stdlib flutter_tts 4.2.5 ships (plugin Kotlin compile failure);
and camera_android_camerax missing `androidx.concurrent:concurrent-futures` on its
compile classpath (javac failure in the plugin). None of these were reachable by
`flutter analyze` or the web build — only a device build finds them, which is
exactly why mobile.yml exists.

**Verified on this machine** (ran, not assumed): `flutter analyze` clean; debug APK
builds; release APK **and** release .aab build on the debug-signing fallback (no
key.properties) — `apksigner` shows `CN=Android Debug`; the key.properties path was
then exercised with a throwaway keystore (scratchpad only, deleted afterwards,
never committed) — `apksigner` shows the throwaway CN, proving the wiring flips to
the upload key when the file exists. mobile.yml parses as valid YAML and mirrors
the least-privilege permissions of the existing green workflows.

**Cannot be verified without accounts / a Mac, by anyone**: the iOS job actually
passing on a macOS runner (no Mac here — first push will tell); pod install /
native iOS compile; that Play accepts the .aab (needs the console account); that
App Store review accepts the app (see blockers); Google Sign-In on store-installed
builds (needs the Play App Signing SHA-1, which exists only after console setup).
One caveat on "green today": CI tracks the latest stable Flutter while this machine
verified on 3.29 — the project pins its own Gradle/AGP/Kotlin so drift is unlikely,
but the first CI run is the proof, not this doc.

## Store-listing blockers (honest list, in dependency order)

1. **App icons are the stock Flutter template icons on BOTH platforms** — verified
   by hash against the Flutter SDK templates, not by eyeballing. The store would
   literally show the Flutter logo. Needs branded icons (1024 master +
   `flutter_launcher_icons` or manual export) before any store listing.
2. **Android home-screen label is lowercase `wasiati`** (`android:label` in the
   manifest); iOS already says "Wasiati". One-word fix, user-visible.
3. **Privacy policy URL** — required by both stores before submission. Must be a
   live page.
4. **Play Data safety form + Apple App Privacy labels** — declare: account data,
   audio/video recordings (legacy messages), voice processed on-device (Ameen),
   the AES-256-GCM client-side vault. Fill honestly; both stores cross-check
   against observed traffic.
5. **Sign in with Apple risk (guideline 4.8)**: the app offers Google Sign-In.
   Apple requires an equivalent privacy-focused login option; plain email+password
   arguably does not satisfy 4.8's "keep email private" clause. Decision for Raed:
   add Sign in with Apple (new OAuth provider, backend + app work) or accept the
   rejection risk on first review.
6. **Account deletion**: Apple 5.1.1(v) and Play both require in-app account
   deletion when accounts exist; Play additionally wants a web deletion URL in the
   Data safety form. Verify a deletion path is actually reachable in the app
   before submitting — several server-side features exist without screens.
7. **Export compliance (iOS)**: the app uses HTTPS and standard AES-GCM (the
   vault) — standard-algorithm use, so answer App Store Connect's encryption
   questions as "standard algorithms only". Optionally set
   `ITSAppUsesNonExemptEncryption` in Info.plist to skip the per-build question —
   only after Raed confirms that classification (a US self-classification report
   and the French declaration are his call, not this doc's).
8. **Screenshots + store copy**: per-device-size screenshots (Apple), phone +
   feature graphic (Play), descriptions in English and Arabic.
9. **Age rating questionnaires** (both stores). Wills and death are the subject
   matter; expect a teen-or-older rating rather than 4+.
10. **Payments presentation on iOS**: features gated by plan must degrade to
    "not available here" — not to a link to web checkout. (US-storefront rules on
    external purchase links loosened in 2025, but CA is a target market and the
    conservative baseline keeps one binary compliant everywhere.)
11. **iOS Google Sign-In return**: `Info.plist` has no reversed-client-id URL
    scheme yet. Not a blocker today (no `GOOGLE_CLIENT_ID_IOS` → button hidden),
    but it must be added together with the iOS OAuth client or the sign-in sheet
    cannot hand control back to the app.
12. **Checkout return UX on mobile**: hosted checkout opens in the browser and
    returns to `app.wasiati.com`, not to the native app — env.dart already notes
    app-links/deep links as the prod fix. Ship-blocking for a polished paid flow
    on Android; on iOS moot while the app shows no checkout at all (§25).
