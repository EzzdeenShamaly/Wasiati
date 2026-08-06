import '../../features/auth/presentation/verify_phone_screen.dart';
import '../../features/auth/presentation/passkey_setup_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/verify_mfa_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/home/presentation/dashboard_screen.dart';
import '../../features/commerce/presentation/pricing_screen.dart';
import '../../features/commerce/presentation/billing_screen.dart';
import '../../features/commerce/presentation/admin/admin_console_screen.dart';
import '../../features/wills/presentation/wills_list_screen.dart';
import '../../features/wills/presentation/create_will_screen.dart';
import '../../features/wills/presentation/will_start_screen.dart';
import '../../features/wills/presentation/will_detail_screen.dart';
import '../../features/wills/presentation/will_document_screen.dart';
import '../../features/wills/presentation/review_seal_screen.dart';
import '../../features/wills/presentation/sealed_screen.dart';
import '../../features/assets/presentation/assets_screen.dart';
import '../../features/ai_intake/domain/ai_intake_models.dart';
import '../../features/ai_intake/presentation/ai_intake_screen.dart';
import '../../features/legacy/presentation/legacy_messages_screen.dart';
import '../../features/files/presentation/video_record_screen.dart';
import '../../features/burial/presentation/burial_screen.dart';
import '../../features/burial/presentation/burial_quotes_admin_screen.dart';
import '../../features/vault/presentation/vault_screen.dart';
import '../../features/identity/presentation/kyc_screen.dart';
import '../../features/referrals/presentation/referrals_screen.dart';
import '../../features/zakat/presentation/zakat_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/death_claims/presentation/death_claims_admin_screen.dart';
import '../../features/admin/presentation/admin_users_screen.dart';
import '../../features/content/presentation/admin_content_screen.dart';
import '../../features/death_claims/presentation/claim_lookup_screen.dart';
import '../../features/death_claims/presentation/claim_submit_screen.dart';
import '../../features/portal/presentation/portal_screen.dart';
import '../../features/confirm/presentation/trustee_confirm_screen.dart';
import '../../features/confirm/presentation/witness_sign_screen.dart';
import '../shell/app_shell.dart';
import '../providers.dart';

// The app has NO home/landing screen of its own — the marketing site (wasiati.com)
// is the home page, and its "Sign in" links straight to the app's sign-in. A signed-out
// visitor to the app therefore starts on /login, not a welcome screen.
const _authAreaRoutes = {
  '/login',
  '/register',
  '/forgot-password',
  '/reset-password',
  '/verify-email',
};

/// The accountless surfaces: the heir & trustee portal, the death-claim flow,
/// and the trustee/witness confirmation links.
///
/// These are reached by people who have NO Wasiati account and never will — a
/// grieving family member following an SMS link, the trustee named on someone
/// else's will, or the witness asked to sign one. They are not part of the auth
/// area (nothing here leads to a sign-in) but they must survive both redirect
/// gates below, and they are matched by PREFIX rather than exact equality
/// because /claim, /trustee and /witness all carry an opaque identifier as a
/// path segment.
bool _isPublicClaimArea(String loc) =>
    loc == '/portal' ||
    loc.startsWith('/claim') ||
    loc.startsWith('/trustee/') ||
    loc.startsWith('/witness/');

bool _isAuthArea(String loc) => _authAreaRoutes.contains(loc) || _isPublicClaimArea(loc);

// Routes a signed-in user should never see (bounce to dashboard). Note that
// /verify-email and /reset-password are allowed while signed in (verifying/resetting).
const _signedInBlocked = {'/login', '/register', '/forgot-password'};

final routerProvider = Provider<GoRouter>((ref) {
  // Bridge Riverpod auth changes into go_router's refresh mechanism.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    routes: [
      // Auth area — no nav shell.
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/verify-mfa', builder: (_, __) => const VerifyMfaScreen()),
      GoRoute(path: '/verify-phone', builder: (_, __) => const VerifyPhoneScreen()),
      // Offered once, straight after phone verification. Skippable, and skipping is
      // remembered — see PasskeyPrefs.
      GoRoute(path: '/passkey-setup', builder: (_, __) => const PasskeySetupScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/reset-password', builder: (_, __) => const ResetPasswordScreen()),
      GoRoute(path: '/verify-email', builder: (_, __) => const VerifyEmailScreen()),

      // Accountless surfaces. Declared OUTSIDE the ShellRoute on purpose: the shell
      // renders the signed-in navigation rail, and an heir reading a relative's will
      // has no dashboard, no wills list and no settings to navigate to.
      //
      // Deliberately NOT added to _signedInBlocked either — a signed-in Wasiati user
      // may perfectly well be an heir or the trustee on someone ELSE's will, and
      // bouncing them to their own dashboard would lock them out of it.
      GoRoute(
        // ?role=heir|trustee is a prefill for the role segment and grants nothing.
        path: '/portal',
        builder: (_, state) => PortalScreen(roleParam: state.uri.queryParameters['role']),
      ),
      GoRoute(path: '/claim', builder: (_, __) => const ClaimLookupScreen()),
      GoRoute(
        // The token is a PATH SEGMENT, not a query string: it keeps the credential
        // out of access logs, Referer headers and browser history.
        path: '/claim/:token',
        builder: (_, state) => ClaimSubmitScreen(token: state.pathParameters['token']!),
      ),
      // The trustee/witness confirmation links from the roster SMS. The id is a
      // roster row id, not a bearer credential — the only thing it unlocks is
      // the ability to text a code to the phone ALREADY on that roster row.
      GoRoute(
        path: '/trustee/:id',
        builder: (_, state) => TrusteeConfirmScreen(trusteeId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/witness/:id',
        builder: (_, state) => WitnessSignScreen(witnessId: state.pathParameters['id']!),
      ),

      // Signed-in app — wrapped in the responsive navigation shell.
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/pricing', builder: (_, __) => const PricingScreen()),
          // We are the billing portal (no Stripe Billing / hosted portal), so this
          // is a real page of ours, reachable from Plans and Settings.
          GoRoute(path: '/billing', builder: (_, __) => const BillingScreen()),
          GoRoute(path: '/admin', builder: (_, __) => const AdminConsoleScreen()),
          GoRoute(path: '/admin/users', builder: (_, __) => const AdminUsersScreen()),
          GoRoute(path: '/admin/death-claims', builder: (_, __) => const DeathClaimsAdminScreen()),
          GoRoute(path: '/admin/content', builder: (_, __) => const AdminContentScreen()),
          GoRoute(path: '/admin/burial-quotes', builder: (_, __) => const BurialQuotesAdminScreen()),
          GoRoute(path: '/wills', builder: (_, __) => const WillsListScreen()),
          GoRoute(path: '/wills/new', builder: (_, __) => const WillStartScreen()),
          // `extra` carries an IntakeSeed when Ameen hands a finished conversation over,
          // so the wizard opens pre-filled with what was understood. Null on a cold start.
          GoRoute(
            path: '/wills/new/form',
            builder: (_, state) => CreateWillScreen(seed: state.extra is IntakeSeed ? state.extra as IntakeSeed : null),
          ),
          GoRoute(
            path: '/wills/:id/review',
            builder: (_, state) => ReviewSealScreen(willId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/wills/:id/sealed',
            builder: (_, state) => SealedScreen(willId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/wills/:id/assets',
            builder: (_, state) => AssetsScreen(willId: state.pathParameters['id']!),
          ),
          // Editing an existing draft through the guided steps. The wizard restores THIS
          // will rather than whichever draft comes back first, which is what let a draft be
          // opened at all: before this, Continue on a draft went to the will detail, whose
          // only forward action is Review & seal — so steps 1 to 5 were unreachable.
          GoRoute(
            path: '/wills/:id/edit',
            builder: (_, state) => CreateWillScreen(willId: state.pathParameters['id']!),
          ),
          // The will document on its own page — the prototype's `willDoc` ("Will export"),
          // reached by Export PDF from the will detail header and the sealed celebration.
          // Declared before the bare '/wills/:id' below, which would otherwise match first.
          GoRoute(
            path: '/wills/:id/document',
            builder: (_, state) => WillDocumentScreen(willId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/wills/:id',
            // `?focus=heirs|witnesses|trustees` scrolls to that section on arrival, so a
            // dashboard tile lands on the thing it names rather than the top of the page.
            builder: (_, state) => WillDetailScreen(
              willId: state.pathParameters['id']!,
              focus: willSectionFrom(state.uri.queryParameters['focus']),
            ),
          ),
          GoRoute(path: '/intake', builder: (_, __) => const AiIntakeScreen()),
          GoRoute(path: '/legacy', builder: (_, __) => const LegacyMessagesScreen()),
          GoRoute(path: '/legacy/record', builder: (_, __) => const VideoRecordScreen()),
          GoRoute(path: '/burial', builder: (_, __) => const BurialScreen()),
          GoRoute(path: '/vault', builder: (_, __) => const VaultScreen()),
          GoRoute(path: '/kyc', builder: (_, __) => const KycScreen()),
          GoRoute(path: '/referrals', builder: (_, __) => const ReferralsScreen()),
          // ?from= is the path zakat was opened from, so its "‹ Back" breadcrumb can
          // return there — `go` replaces the stack, leaving nothing to pop.
          GoRoute(
            path: '/zakat',
            builder: (_, state) => ZakatScreen(from: state.uri.queryParameters['from']),
          ),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        ],
      ),
    ],
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final onSplash = loc == '/';
      return switch (auth) {
        // COLD LOAD. This branch is the second gate, and it is the one that is easy
        // to miss: _isAuthArea above only governs the signed-OUT case, but on a cold
        // start auth is AuthInitial and EVERY path was being sent to the splash
        // screen — which then lands on /login. A family member clicking the landing
        // footer's "Heir & trustee portal" link would have bounced straight to a
        // sign-in form for an account they do not have, and the whole feature would
        // have been dead on arrival while looking wired up. Exempting the same paths
        // here is what actually makes the deep link work.
        AuthInitial() => (onSplash || _isPublicClaimArea(loc)) ? null : '/',
        AuthAwaitingMfa() => loc == '/verify-mfa' ? null : '/verify-mfa',
        AuthSignedIn(:final user) => (onSplash || _signedInBlocked.contains(loc) || loc == '/verify-mfa')
            ? '/dashboard'
            : (loc.startsWith('/admin') && user.role != 'ADMIN' ? '/dashboard' : null),
        AuthSignedOut() => _isAuthArea(loc) ? null : '/login',
      };
    },
  );
});
