import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App locale. `null` means "follow the device" (the MaterialApp resolves it
/// against supportedLocales). The Settings language row flips it to an explicit
/// English or Arabic. Kept in memory, matching [themeModeProvider]'s pattern.
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() => null; // system

  void set(Locale? locale) => state = locale;

  void useEnglish() => state = const Locale('en');
  void useArabic() => state = const Locale('ar');
  void useSystem() => state = null;
}

final localeProvider = NotifierProvider<LocaleController, Locale?>(LocaleController.new);

/// The two languages Wasiati ships in the app today.
const supportedAppLocales = [Locale('en'), Locale('ar')];
