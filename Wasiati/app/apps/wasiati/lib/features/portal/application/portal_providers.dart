import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/portal_client.dart';
import '../data/portal_api.dart';
import '../domain/portal_models.dart';

/// The portal's own Dio — NOT apiClientProvider. See portal_client.dart for why
/// routing these calls through the authenticated client would sign a real user out
/// of their own account when a portal session lapses.
final portalClientProvider = Provider<PortalClient>((ref) => PortalClient.create());

final portalApiProvider = Provider<PortalApi>((ref) => PortalApi(ref.read(portalClientProvider).dio));

/// Which of the three panels the single /portal route is showing. All three live
/// in ONE route so the session token never reaches the URL, the history stack, or
/// a Referer header.
enum PortalStep { signIn, code, view }

class PortalState {
  final PortalStep step;
  final PortalRole role;
  final String email;

  /// The opaque session token. In memory ONLY — never persisted, never in the URL.
  final String? token;

  final PortalMe? me;
  final PortalClaim? claim;
  final PortalWill? will;

  /// Every legacy video on the released will, OLDEST first (the order they were
  /// recorded, which is the order to watch them). Empty means there are none.
  final List<PortalVideo> videos;

  /// True once the videos have been asked for, so a will with none does not
  /// re-request on every rebuild.
  final bool videosChecked;

  final bool busy;
  /// The failure itself, not a pre-rendered sentence.
  ///
  /// Held as the object so the SCREEN decides the wording — see localizedApiMessage. It
  /// used to be a String built in this controller, which had no locale and therefore no
  /// choice but to hardcode English.
  final Object? error;

  const PortalState({
    this.step = PortalStep.signIn,
    this.role = PortalRole.heir,
    this.email = '',
    this.token,
    this.me,
    this.claim,
    this.will,
    this.videos = const [],
    this.videosChecked = false,
    this.busy = false,
    this.error,
  });

  /// The Continue button's gate, exactly as the prototype has it: an address that
  /// contains '@'.
  bool get canContinue => email.contains('@');

  PortalState copyWith({
    PortalStep? step,
    PortalRole? role,
    String? email,
    String? token,
    PortalMe? me,
    PortalClaim? claim,
    PortalWill? will,
    List<PortalVideo>? videos,
    bool? videosChecked,
    bool? busy,
    Object? error,
    bool clearError = false,
  }) =>
      PortalState(
        step: step ?? this.step,
        role: role ?? this.role,
        email: email ?? this.email,
        token: token ?? this.token,
        me: me ?? this.me,
        claim: claim ?? this.claim,
        will: will ?? this.will,
        videos: videos ?? this.videos,
        videosChecked: videosChecked ?? this.videosChecked,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );
}

class PortalController extends Notifier<PortalState> {
  @override
  PortalState build() => const PortalState();

  PortalApi get _api => ref.read(portalApiProvider);

  /// Preselects the role from `?role=heir|trustee` on the deep link. The role is a
  /// PREFILL ONLY and grants nothing — the recipient still does email → code.
  void prefillRole(String? raw) {
    final r = switch (raw?.toLowerCase()) {
      'heir' => PortalRole.heir,
      'trustee' => PortalRole.trustee,
      _ => null,
    };
    if (r != null && state.step == PortalStep.signIn) setRole(r);
  }

  void setRole(PortalRole role) => state = state.copyWith(role: role, clearError: true);
  void setEmail(String email) => state = state.copyWith(email: email, clearError: true);

  /// Step 1 → 2. The backend answers identically whether or not the address is on a
  /// will, so this advances on any success; it is not, and must not read as, a
  /// confirmation that the address is known.
  Future<void> requestCode() async {
    if (!state.canContinue || state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _api.start(role: state.role, email: state.email.trim());
      state = state.copyWith(step: PortalStep.code, busy: false);
    } catch (e) {
      state = state.copyWith(busy: false, error: e);
    }
  }

  /// Resend from the code step — same call, without moving the step.
  Future<void> resendCode() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _api.start(role: state.role, email: state.email.trim());
    } catch (_) {
      // The endpoint is uniform by design; a resend has nothing to report.
    }
    state = state.copyWith(busy: false);
  }

  /// Step 2 → 3. Every failure returns the same message from the backend, so this
  /// surfaces it verbatim rather than branching.
  Future<bool> verifyCode(String code) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final session = await _api.verify(role: state.role, email: state.email.trim(), code: code);
      state = state.copyWith(
        token: session.token,
        step: PortalStep.view,
        busy: false,
        me: PortalMe(role: session.role, estateName: session.estateName, claimStatus: session.claimStatus),
        role: session.role,
      );
      await refresh();
      return true;
    } catch (e) {
      state = state.copyWith(busy: false, error: e);
      return false;
    }
  }

  /// Loads whatever this session is entitled to see. /portal/claim is the ONLY
  /// endpoint that reveals status — the 403 from /portal/will is identical across
  /// every unreleased state, so the will is only fetched once claim says RELEASED.
  Future<void> refresh() async {
    final token = state.token;
    if (token == null) return;
    try {
      // /portal/me first: it carries trusteeAcceptancePending, and a trustee who never
      // accepted the role is refused the will. Without this the released branch below would
      // walk straight into a 403 and render it as a generic error, hiding the one action
      // that fixes it. verifyCode's PortalMe is built from the sign-in response, which does
      // not carry the flag — so it has to be re-read here, and again after accepting.
      final me = await _api.me(token);
      state = state.copyWith(me: me);
      final claim = await _api.claim(token);
      state = state.copyWith(claim: claim);
      if (claim.status == ClaimStatus.released && !me.trusteeAcceptancePending) {
        final will = await _api.will(token);
        state = state.copyWith(will: will);
        if (!state.videosChecked) {
          state = state.copyWith(videosChecked: true);
          try {
            state = state.copyWith(videos: await _api.videos(token));
          } catch (_) {
            // Best-effort: the will itself is already on screen, and a failed
            // video fetch must not take the released view down with it.
          }
        }
      }
    } catch (e) {
      if (_isSessionOver(e)) {
        sessionExpired(e);
      } else {
        state = state.copyWith(error: e);
      }
    }
  }

  /// HEIR: record readiness for release.
  Future<void> confirmRelease() async {
    final token = state.token;
    if (token == null || state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _api.confirm(token);
      state = state.copyWith(busy: false);
      await refresh();
    } catch (e) {
      if (_isSessionOver(e)) {
        sessionExpired(e);
      } else {
        state = state.copyWith(busy: false, error: e);
      }
    }
  }

  /// A video URL that is valid RIGHT NOW, fetched at the moment of the tap.
  ///
  /// Presigned download URLs live 300 seconds (s3-storage.provider.ts). The list — and the
  /// URLs embedded in it — was fetched once per session behind `if (!state.videosChecked)`
  /// and never again. So a daughter who signed in, read her father's written message, read
  /// the division of the estate and downloaded the PDF would tap "A video message for you"
  /// eight minutes later and get S3's raw XML: AccessDenied, Request has expired.
  ///
  /// And silently: an expired presigned URL is still a well-formed https URL, so
  /// safeLaunchExternal succeeded, onError never fired, and no snackbar appeared. Her only
  /// recovery was to exit, request a new emailed code and sign in again — which nothing on
  /// the screen told her.
  ///
  /// Re-fetching the whole list rather than one URL keeps this to the endpoint that already
  /// exists, and refreshes every other card's URL in the same breath.
  Future<String?> freshVideoUrl(String fileId) async {
    final token = state.token;
    if (token == null) return null;
    try {
      final videos = await _api.videos(token);
      state = state.copyWith(videos: videos);
      for (final v in videos) {
        if (v.fileId == fileId) return v.url;
      }
      return null; // the object is gone — the purge may have run
    } catch (e) {
      if (_isSessionOver(e)) sessionExpired(e);
      return null;
    }
  }

  /// TRUSTEE: accept the role, which is what opens the estate.
  ///
  /// A trustee named on the will but never confirmed can sign in and see that they are
  /// expected — but not read anything, and not override the heirs. This is the one tap that
  /// changes that, and it exists here because the only other route to CONFIRMED is an
  /// invitation link mailed out when the will was written.
  Future<void> acceptTrusteeship() async {
    final token = state.token;
    if (token == null || state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _api.acceptTrusteeship(token);
      state = state.copyWith(busy: false);
      await refresh(); // re-reads /portal/me, so the estate appears in the same beat
    } catch (e) {
      if (_isSessionOver(e)) {
        sessionExpired(e);
      } else {
        state = state.copyWith(busy: false, error: e);
      }
    }
  }

  /// TRUSTEE: release without the full heir roll-call. Recorded, never silent.
  Future<void> overrideRelease() async {
    final token = state.token;
    if (token == null || state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _api.override(token);
      state = state.copyWith(busy: false);
      await refresh();
    } catch (e) {
      if (_isSessionOver(e)) {
        sessionExpired(e);
      } else {
        state = state.copyWith(busy: false, error: e);
      }
    }
  }

  /// Burns the token server-side, then drops every trace from memory.
  Future<void> exit() async {
    final token = state.token;
    if (token != null) {
      try {
        await _api.exit(token);
      } catch (_) {
        // The local session is being discarded either way.
      }
    }
    state = const PortalState();
  }


  /// True when the portal session itself is finished rather than one call failing.
  ///
  /// The guard returns 401 for a token that is unknown, expired OR consumed, with
  /// one message and no oracle. PORTAL_TOKEN_TTL_HOURS defaults to 12, so a heir
  /// who leaves the tab open overnight and comes back to confirm hits exactly this.
  /// Leaving them on the read-only screen would show stale data behind an error
  /// line while every further tap failed the same way; dropping to the sign-in step
  /// tells them the truth and hands them the way back in.
  bool _isSessionOver(Object e) => e is ApiException && e.statusCode == 401;

  /// Discards a dead session, keeping the role and address so the sign-in step is
  /// one tap and one code away rather than a blank form.
  ///
  /// Public so the transition can be tested directly — it is the one state change
  /// here that a reader hits without doing anything, and getting it wrong strands
  /// them on a screen of stale data.
  void sessionExpired(Object failure) {
    state = PortalState(role: state.role, email: state.email, error: failure);
  }
}

final portalControllerProvider =
    NotifierProvider<PortalController, PortalState>(PortalController.new);
