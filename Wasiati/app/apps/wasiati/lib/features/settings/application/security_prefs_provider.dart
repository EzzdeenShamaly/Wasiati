import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Device-local biometric unlock preferences (prototype "Settings" → Security):
/// Face ID to open the app, and Face ID to open the vault. Kept in memory,
/// matching [themeModeProvider] / [localeProvider] — a per-device UI preference,
/// not account state synced to the server.
class SecurityPrefs {
  final bool faceUnlockApp;
  final bool faceUnlockVault;
  const SecurityPrefs({this.faceUnlockApp = false, this.faceUnlockVault = false});

  SecurityPrefs copyWith({bool? faceUnlockApp, bool? faceUnlockVault}) => SecurityPrefs(
        faceUnlockApp: faceUnlockApp ?? this.faceUnlockApp,
        faceUnlockVault: faceUnlockVault ?? this.faceUnlockVault,
      );
}

class SecurityPrefsController extends Notifier<SecurityPrefs> {
  @override
  SecurityPrefs build() => const SecurityPrefs();

  void toggleFaceApp() => state = state.copyWith(faceUnlockApp: !state.faceUnlockApp);
  void toggleFaceVault() => state = state.copyWith(faceUnlockVault: !state.faceUnlockVault);
}

final securityPrefsProvider =
    NotifierProvider<SecurityPrefsController, SecurityPrefs>(SecurityPrefsController.new);
