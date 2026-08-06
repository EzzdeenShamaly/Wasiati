import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';
import 'core/l10n/l10n.dart';
import 'core/locale/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/theme_mode_provider.dart';

void main() {
  runApp(const ProviderScope(child: WasiatiApp()));
}

class WasiatiApp extends ConsumerWidget {
  const WasiatiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appName,
      debugShowCheckedModeBanner: false,
      theme: WasiatiTheme.light(),
      darkTheme: WasiatiTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      // Text selection is wired at the page BODIES (AppShell for the signed-in app,
      // AuthScaffold for the auth/public screens), not here: SelectionArea needs an Overlay
      // ancestor, and this builder sits ABOVE the router's Navigator — the one that provides
      // the Overlay — so a SelectionArea here throws "No Overlay widget found".
    );
  }
}
