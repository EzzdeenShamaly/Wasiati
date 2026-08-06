import 'package:flutter/material.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

/// How many steps the will flow has, end to end.
///
/// Six, matching the prototype's `stepNames`: Family & heirs · Heir registry ·
/// Witnesses, trustee & guardian · Your estate & bequest · Wishes & words ·
/// Review & confirm. Only the first five live in the create wizard — the sixth is the
/// Review & seal page — which is why this constant is shared rather than owned by either.
const int kWillFlowSteps = 6;

/// The progress bar for the will flow.
///
/// Lives here, not inside the wizard, because the flow does not end there. The wizard
/// drew six segments and the Review page drew none, so the bar simply vanished on the
/// last step: the owner watched it reach five of six and then lose it entirely on the
/// screen that completes the flow. Both screens now render the same bar, and it is
/// accurate on both.
///
/// [step] is 1-based over the whole flow (1..[kWillFlowSteps]), not a wizard index.
class WillStepBar extends StatelessWidget {
  const WillStepBar({super.key, required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var i = 1; i <= kWillFlowSteps; i++) ...[
        if (i > 1) const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: i <= step ? WasiatiColors.brassGold : context.tokens.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    ]);
  }
}
