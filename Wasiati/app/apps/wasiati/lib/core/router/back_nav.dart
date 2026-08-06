import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// "Back" that means back.
///
/// The app navigates almost entirely with `go()`, which REPLACES the route stack. Every
/// back control was therefore written as another `go()` to a hard-coded destination — and
/// a hard-coded destination is a guess about where you came from. It was wrong in exactly
/// the places it mattered: "Edit assets & loans" on step 4 of the wizard is a real
/// `push()`, so the wizard is still on the stack underneath, but the assets screen's back
/// went `go('/wills/:id')` and dropped the owner on the will dashboard with the half-filled
/// form discarded. Same for the review step: back left the flow entirely.
///
/// So: pop when there is genuinely something to pop, and fall back to the sensible
/// destination only when there is not — a fresh tab opened straight on a deep link, or a
/// screen reached by a replacing `go()`.
extension BackNav on BuildContext {
  /// Pops if this screen was pushed onto something; otherwise navigates to [fallback].
  void goBack(String fallback) {
    if (canPop()) {
      pop();
    } else {
      go(fallback);
    }
  }
}
