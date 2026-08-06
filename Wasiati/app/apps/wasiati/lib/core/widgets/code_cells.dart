import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

/// Six code cells over a hidden input. The cell at the caret position gets the
/// gold focus border + ring (spec: 44×52, r12, 1.5px border).
///
/// Lifted out of verify_mfa_screen so MFA, the claim flow and the heir/trustee
/// portal all present the same one-time-code affordance. It lives in core/widgets
/// rather than the design system because it is app furniture — it depends only on
/// [context.tokens], but the design package has no notion of "a 6-digit OTP".
///
/// NOTE ON DIGITS: the code is an identifier, not a quantity, so it is NEVER run
/// through context.digits() — Arabic-Indic OTP digits do not match what arrives by
/// SMS and cannot be typed back on a numeric keypad. See l10n.dart:33-35.
class CodeCells extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCompleted;
  final VoidCallback onChanged;

  /// Accessible name for the (visually hidden) field the cells sit over. Icon-only
  /// and painted controls need one — the cells themselves are decoration.
  final String semanticLabel;

  const CodeCells({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCompleted,
    required this.onChanged,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final code = controller.text;
    // The group lives HERE rather than on each screen that shows a code. Five screens mount
    // this widget — login MFA, phone verification, password reset, the witness/trustee
    // confirm flow and the heir portal — and none had one, so the oneTimeCode hint below
    // would have stayed inert in all five. A one-time code is also a self-contained
    // autofill context: it shares nothing with the email or password fields elsewhere on
    // the page, so scoping the group to the widget is the correct shape, not a shortcut.
    return AutofillGroup(
      child: GestureDetector(
        onTap: () => focusNode.requestFocus(),
        child: Stack(children: [
        // The painted cells carry no semantics of their own — the real TextField
        // beneath is the focusable, labelled control a screen reader lands on.
        ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (i) {
              final active = i == code.length || (code.length == 6 && i == 5);
              final filled = i < code.length;
              return Container(
                width: 44,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: active ? tokens.gold : tokens.hairline, width: active ? 1.8 : 1.5),
                  boxShadow: active
                      ? [BoxShadow(color: tokens.gold.withValues(alpha: 0.25), blurRadius: 0, spreadRadius: 3)]
                      : null,
                ),
                child: Text(filled ? code[i] : '',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              );
            }),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              keyboardType: TextInputType.number,
              // Lets the platform fill the code it just watched arrive: iOS offers it above
              // the keyboard, Android autofills it, Chrome reads it via WebOTP. Every code
              // in the product comes through this one widget — login MFA, phone
              // verification, password reset, step-up re-auth — so the hint belongs here
              // rather than repeated at each call site.
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              showCursor: false,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              decoration: InputDecoration(
                counterText: '',
                border: InputBorder.none,
                labelText: semanticLabel,
              ),
              onChanged: (v) {
                onChanged();
                if (v.length == 6) onCompleted();
              },
            ),
          ),
          ),
        ]),
      ),
    );
  }
}

/// The 30-second resend countdown shared by MFA and the portal.
///
/// Owns only the ticking integer; the caller renders it. Extracted alongside
/// [CodeCells] because every screen that shows the cells also has to say "you can
/// ask for another code in Ns" and none of them should re-implement the timer.
class ResendCountdown extends StatefulWidget {
  final int seconds;

  /// Builds the row. [secondsLeft] is 0 once the countdown has run out, at which
  /// point [restart] is the "send another" action.
  final Widget Function(BuildContext context, int secondsLeft, VoidCallback restart) builder;

  const ResendCountdown({super.key, this.seconds = 30, required this.builder});

  @override
  State<ResendCountdown> createState() => ResendCountdownState();
}

class ResendCountdownState extends State<ResendCountdown> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _left = widget.seconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 0) {
        t.cancel();
      } else {
        setState(() => _left--);
      }
    });
  }

  /// Restarts the countdown — call after a successful resend.
  void restart() => setState(_start);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _left, restart);
}
