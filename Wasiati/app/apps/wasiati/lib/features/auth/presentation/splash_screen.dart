import 'package:flutter/material.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

/// Shown while the app probes for a resumable session on boot.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Seal(size: 72, status: SealStatus.locked),
            SizedBox(height: 24),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: WasiatiColors.brassGold),
            ),
          ],
        ),
      ),
    );
  }
}
