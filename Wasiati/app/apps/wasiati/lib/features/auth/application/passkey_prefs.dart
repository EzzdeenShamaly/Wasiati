import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local memory about passkeys. Two facts, both deliberately NOT on the server.
///
///  · Whether we have already offered to set one up. Asking once is a nudge; asking on
///    every visit is nagging, and nagging about security is how people learn to dismiss
///    security prompts without reading them.
///  · Whether a passkey exists ON THIS DEVICE. A passkey is bound to the device that
///    created it, so "this account has a passkey" is the wrong question — the right one is
///    "can THIS machine use one", which only this machine can answer. It drives the login
///    screen's ordering: someone who has a passkey here should be shown it first rather
///    than reaching for the password out of habit and paying for a text.
///
/// Both are hints, never authority. Losing them (cleared storage, new device) costs one
/// extra prompt or one wrongly-ordered button, never access — the server decides what a
/// user may actually do.
class PasskeyPrefs {
  static const _promptedKey = 'passkey_prompt_seen_v1';
  static const _onDeviceKey = 'passkey_on_this_device_v1';

  /// Bounded on purpose.
  ///
  /// `getInstance()` does not merely fail when the platform channel is unavailable — it can
  /// HANG, never completing. Awaiting that on a sign-in path would leave the user staring at
  /// a spinner forever over a stored boolean, and it is exactly what happened in a widget
  /// test (pumpAndSettle timed out) before this timeout existed. A preference is a hint;
  /// nothing here is worth blocking on.
  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Unavailable, or too slow to matter (private browsing, a locked profile, no channel
      // at all in tests). Every read then answers "unknown", which costs at most one extra
      // prompt or one wrongly-ordered button — never access, and never a stuck screen.
      return null;
    }
  }

  /// Reads a flag, tolerating a value of the WRONG TYPE.
  ///
  /// `getBool` THROWS when the stored value is not a bool, which is what a renamed key or a
  /// store written by an older build looks like — and an exception here would take the login
  /// screen down with it, since this is read during initState. Anything unreadable answers
  /// "no", which only ever costs a prompt or an un-promoted button.
  Future<bool> _flag(String key) async {
    try {
      return (await _prefs())?.getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _setFlag(String key) async {
    try {
      await (await _prefs())?.setBool(key, true);
    } catch (_) {
      // Nothing to do: these are hints, and losing one costs a repeat prompt at most.
    }
  }

  Future<bool> hasBeenPrompted() => _flag(_promptedKey);

  Future<void> markPrompted() => _setFlag(_promptedKey);

  Future<bool> hasPasskeyOnThisDevice() => _flag(_onDeviceKey);

  /// Recorded after a successful enrolment, and after a successful passkey SIGN-IN — the
  /// second matters because a device may hold a passkey this install never created (a
  /// synced iCloud/Google keychain, or a reinstall).
  Future<void> markPasskeyOnThisDevice() async {
    await _setFlag(_onDeviceKey);
    // Someone who has one plainly does not need to be offered one.
    await _setFlag(_promptedKey);
  }
}

final passkeyPrefsProvider = Provider<PasskeyPrefs>((ref) => PasskeyPrefs());
