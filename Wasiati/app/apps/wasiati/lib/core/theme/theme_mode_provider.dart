import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App theme mode. Defaults to following the OS ("Match system"); the Settings
/// screen and the rail/auth theme pill flip it to explicit light/dark.
///
/// An explicit choice is remembered per device. "System" is the *absence* of a
/// choice, so choosing it clears the key rather than writing "system" — that way
/// a fresh install and a user who has gone back to "Match system" are the same
/// state, and neither pins the app to whatever brightness it booted with.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _prefsKey = 'wasiati_theme_mode';

  @override
  ThemeMode build() {
    // Synchronous default so the first frame renders in the OS theme rather than
    // flashing light and correcting; the stored choice lands a tick later.
    _restore();
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    final stored = await _read();
    // A theme flip during the read would otherwise be clobbered by the restore.
    if (stored != null && state == ThemeMode.system) state = stored;
  }

  Future<ThemeMode?> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return switch (prefs.getString(_prefsKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => null,
      };
    } catch (_) {
      return null; // no prefs backend (tests, unsupported platform) — follow the OS
    }
  }

  Future<void> _persist(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mode == ThemeMode.system) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, mode == ThemeMode.dark ? 'dark' : 'light');
      }
    } catch (_) {/* preference is cosmetic — never break the app over it */}
  }

  void set(ThemeMode mode) {
    state = mode;
    _persist(mode);
  }

  /// Toggle used by the theme pill. From "system" it commits to the opposite of
  /// the current platform brightness so the tap always visibly flips.
  void toggle(Brightness platformBrightness) {
    set(switch (state) {
      ThemeMode.system => platformBrightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
    });
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
