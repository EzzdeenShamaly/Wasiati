import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati_design_system/wasiati_design_system.dart';

/// WCAG 2.1 contrast guards for the brand palette.
///
/// These exist because "the font colour is barely readable in dark mode" was a
/// bug report, not a hypothesis: gold type on a night card measured 2.82:1 and the
/// net-estate figure 1.59:1, because light-theme inks were hard-coded into screens
/// that render in both themes. Contrast is cheap to compute and expensive to
/// eyeball, so it is asserted here rather than left to review.
///
/// AA is 4.5:1 for body text and 3:1 for the visual boundary of a control
/// (WCAG 1.4.11). Numbers in the reasons are the measured values at the time of
/// writing — if one moves, the palette moved.
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color fg, Color bg) {
  final a = _lum(fg), b = _lum(bg);
  final hi = a > b ? a : b, lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void main() {
  group('gold type (tokens.goldInk)', () {
    test('clears AA on both themes\' card surfaces', () {
      expect(_contrast(WasiatiTokens.dark.goldInk, WasiatiColors.nightSurface),
          greaterThanOrEqualTo(4.5)); // 6.55:1
      expect(_contrast(WasiatiTokens.light.goldInk, WasiatiColors.parchmentLight),
          greaterThanOrEqualTo(4.5)); // 4.76:1
    });

    test('clears AA on the dark brassGold @10% wash callouts sit on', () {
      final darkWash = _over(WasiatiColors.brassGold.withValues(alpha: 0.10), WasiatiColors.nightSurface);
      expect(_contrast(WasiatiTokens.dark.goldInk, darkWash), greaterThanOrEqualTo(4.5)); // 5.80:1
    });

    test('light gold on its wash clears AA', () {
      // Was "light gold on its wash is short of AA — PRE-EXISTING, not this change",
      // pinned at >4.2 with a note saying the callouts "want either a darker ink or a
      // paler wash". They got both: goldDeep went #8A6222 -> #845E21 with the rest of the
      // light text ladder, and the two chips that paint gold type on a wash of their own
      // colour (burial's estimate-only chip, the admin promo status pill) dropped from 12%
      // to 8%.
      //
      // Asserted on parchmentLight only, because that is where both chips actually live —
      // each sits inside a card (burial_screen.dart:225, the admin promo table row), never
      // on the raw parchment background. Worth stating plainly: on parchment NO alpha
      // reaches 4.5 for gold-on-its-own-wash, topping out at 4.35 even at 4%. If one of
      // these chips is ever moved onto the page background, the wash cannot save it and
      // the ink has to change.
      final wash = _over(WasiatiColors.goldDeep.withValues(alpha: 0.08), WasiatiColors.parchmentLight);
      expect(_contrast(WasiatiTokens.light.goldInk, wash), greaterThanOrEqualTo(4.5),
          reason: 'gold type on an 8% gold wash over a card must clear AA');
    });

    test('regression: the inks that caused the bug still fail, so the token is load-bearing', () {
      // goldDeep in dark was the reported "barely readable" text.
      expect(_contrast(WasiatiColors.goldDeep, WasiatiColors.nightSurface), lessThan(4.5)); // 2.82:1
      // ...and the accent gold is not a substitute for type on light.
      expect(_contrast(WasiatiColors.brassGold, WasiatiColors.parchmentLight), lessThan(4.5)); // 3.30:1
    });

    test('a gold FIELD carrying a light label uses goldDeep, never raw brassGold', () {
      // The other half of the sweep. Five places built a gold pill or button out of raw
      // brassGold and put a light label on it: the COMPED chip, the "INCLUDED IN YOUR
      // PLAN" badge, the yearly-saving pill, the heir's Confirm-release CTA and the admin
      // Release button. colors.dart had already recorded that pairing as rejected at
      // 3.22:1 when the gold CTA was built — the screens simply did not get the message.
      for (final label in const [WasiatiColors.onDark, WasiatiColors.parchmentLight]) {
        expect(_contrast(label, WasiatiColors.brassGold), lessThan(4.5),
            reason: 'brassGold is a fill/ring colour: it cannot carry a light label');
        expect(_contrast(label, WasiatiColors.goldDeep), greaterThanOrEqualTo(4.5),
            reason: 'goldDeep is the field that can');
      }
    });
  });

  group('the gold CTA (WasiatiButtons.goldSolid)', () {
    // DECISIONS §16. A fill carrying a label owes the type bar, and brassGold could
    // not pay it. Both ends of the button move together: field and label.
    test('the label clears AA on both themes\' fields', () {
      expect(_contrast(WasiatiColors.onDark, WasiatiColors.goldDeep), greaterThanOrEqualTo(4.5)); // 4.63:1
      expect(_contrast(WasiatiColors.inkNavy, WasiatiColors.goldDeepDark), greaterThanOrEqualTo(4.5)); // 6.70:1
    });

    test('the button is still findable — its field clears 3:1 on every surface it sits on', () {
      // WCAG 1.4.11 for a UI component. This is the half a darker field could have
      // broken: goldDeep on a night card is only 2.82:1, which is why the dark end
      // swaps up the scale rather than down. create_will mounts it on nightRaised.
      for (final light in [WasiatiColors.parchmentLight, WasiatiColors.parchment]) {
        expect(_contrast(WasiatiColors.goldDeep, light), greaterThanOrEqualTo(3.0)); // 4.76:1 / 4.28:1
      }
      for (final night in [WasiatiColors.nightSurface, WasiatiColors.nightRaised, WasiatiColors.nightBg]) {
        expect(_contrast(WasiatiColors.goldDeepDark, night), greaterThanOrEqualTo(3.0)); // 6.55:1 / 5.84:1 / 7.39:1
      }
    });

    test('regression: why the field had to move at all, and why one gold cannot serve both', () {
      // brassGold as a field fails the label bar at labelLarge's 15px/w600...
      expect(_contrast(WasiatiColors.onDark, WasiatiColors.brassGold), lessThan(4.5)); // 3.22:1
      // ...and no permitted ink rescues it: inkNavy is the darkest in the palette and
      // still misses. Only black would clear, and black is not a UI colour here.
      expect(_contrast(WasiatiColors.inkNavy, WasiatiColors.brassGold), lessThan(4.5)); // 4.15:1
      // The constraints that forced the swap: a dark-theme field dark enough to carry
      // onDark is too dark to be found on a night card.
      expect(_contrast(WasiatiColors.onDark, WasiatiColors.goldDeep), greaterThanOrEqualTo(4.5)); // 4.63:1
      expect(_contrast(WasiatiColors.goldDeep, WasiatiColors.nightRaised), lessThan(3.0)); // 2.51:1
    });
  });

  group('semantic type (tokens.dangerInk / successInk / warningInk / infoInk)', () {
    // The raw semantic constants are FILLS. As type they failed AA on the night
    // surfaces — the same defect as the gold ink, reported the same way. Unlike
    // --goldDeep the prototype does not theme-swap these, so both ends are ours to
    // hold: see DECISIONS §14.
    Color inkOf(WasiatiTokens t, String name) => switch (name) {
          'danger' => t.dangerInk,
          'success' => t.successInk,
          'info' => t.infoInk,
          _ => t.warningInk,
        };

    for (final name in ['danger', 'success', 'warning', 'info']) {
      test('$name ink clears AA on both themes\' card + raised surfaces', () {
        // Raised is the harder of the two dark fields, so it is the binding case.
        // dark: 5.08/4.53 · 5.07/4.52 · 6.50/5.80 · 5.11/4.56  (surface/raised)
        expect(_contrast(inkOf(WasiatiTokens.dark, name), WasiatiColors.nightSurface),
            greaterThanOrEqualTo(4.5));
        expect(_contrast(inkOf(WasiatiTokens.dark, name), WasiatiColors.nightRaised),
            greaterThanOrEqualTo(4.5));
        // light: 5.87/5.28 · 5.04/4.53 · 5.10/4.59 · 6.64/5.97  (parchmentLight/parchment)
        expect(_contrast(inkOf(WasiatiTokens.light, name), WasiatiColors.parchmentLight),
            greaterThanOrEqualTo(4.5));
        expect(_contrast(inkOf(WasiatiTokens.light, name), WasiatiColors.parchment),
            greaterThanOrEqualTo(4.5));
      });
    }

    test('warning ink reads on the warningTint chips it sits inside', () {
      // assets_screen's kind chip and suggestion chip put warning type directly on a
      // wash of itself. The tints stay raw (they are fills); only the type moved.
      final darkChip = _over(WasiatiColors.warningTintDark, WasiatiColors.nightSurface);
      final darkChipRaised = _over(WasiatiColors.warningTintDark, WasiatiColors.nightRaised);
      final lightChip = _over(WasiatiColors.warningTintLight, WasiatiColors.parchmentLight);
      expect(_contrast(WasiatiTokens.dark.warningInk, darkChip), greaterThanOrEqualTo(4.5)); // 5.05:1
      expect(_contrast(WasiatiTokens.dark.warningInk, darkChipRaised), greaterThanOrEqualTo(4.5)); // 4.51:1
      expect(_contrast(WasiatiTokens.light.warningInk, lightChip), greaterThanOrEqualTo(4.5)); // 4.52:1
    });

    test('the snackbar fields carry onDark at AA', () {
      // The ink/fill split exempts fills from the type bar, but only fills nothing is
      // read on. A snack is a fill with a label: `success` carries onDark at just
      // 4.24:1, so WasiatiSnack takes successDeep (4.91:1). danger already cleared.
      expect(_contrast(WasiatiColors.onDark, WasiatiColors.successDeep),
          greaterThanOrEqualTo(4.5)); // 4.91:1
      expect(_contrast(WasiatiColors.onDark, WasiatiColors.danger),
          greaterThanOrEqualTo(4.5)); // 5.72:1
      // The field it replaced. This is palette math, so it does not catch an edit to
      // WasiatiSnack itself — but it does stop the two greens being collapsed, or
      // successDeep drifting back toward `success` as a "fidelity fix".
      expect(_contrast(WasiatiColors.onDark, WasiatiColors.success), lessThan(4.5)); // 4.24:1
    });

    test('seal + checkbox glyphs clear the 3:1 bar for graphical objects', () {
      // The other two places onDark-ish parchment sits on a raw `success` body. Both
      // are glyphs, not copy, so WCAG 1.4.11's 3:1 applies rather than 4.5 — which is
      // why the snack moved and these did not.
      expect(_contrast(WasiatiColors.onDark, WasiatiColors.success), greaterThanOrEqualTo(3.0)); // 4.24:1
      expect(_contrast(WasiatiColors.parchmentLight, WasiatiColors.success),
          greaterThanOrEqualTo(3.0)); // 4.36:1
    });

    test('regression: the raw fills still fail as type, so the tokens are load-bearing', () {
      // The reported dark cases: the Sign out row and the DEBTS figure. info was the
      // worst of the four — the SUBMITTED claim status and the dashboard witnesses
      // tile — and at 1.80:1 on nightRaised its status dot missed even the 3:1 bar
      // for a graphical object (WCAG 1.4.11), which is why the dot took the ink too.
      expect(_contrast(WasiatiColors.danger, WasiatiColors.nightSurface), lessThan(4.5)); // 2.28:1
      expect(_contrast(WasiatiColors.success, WasiatiColors.nightSurface), lessThan(4.5)); // 3.08:1
      expect(_contrast(WasiatiColors.warning, WasiatiColors.nightSurface), lessThan(4.5)); // 4.17:1
      expect(_contrast(WasiatiColors.info, WasiatiColors.nightSurface), lessThan(4.5)); // 2.02:1
      expect(_contrast(WasiatiColors.info, WasiatiColors.nightRaised), lessThan(3.0)); // 1.80:1
      // ...and the light end was NOT safe either, which is why both ends moved:
      // warning as parchment type is a worse miss (3.22:1) than its dark case, and
      // worse still (2.85:1) on its own chip tint. success was 4.36:1.
      expect(_contrast(WasiatiColors.warning, WasiatiColors.parchmentLight), lessThan(3.5)); // 3.22:1
      expect(_contrast(WasiatiColors.success, WasiatiColors.parchmentLight), lessThan(4.5)); // 4.36:1
      // danger and info were already fine on parchment — hence each is its own light ink.
      expect(_contrast(WasiatiTokens.light.dangerInk, WasiatiColors.parchmentLight),
          greaterThanOrEqualTo(4.5)); // 5.87:1
      expect(_contrast(WasiatiTokens.light.infoInk, WasiatiColors.parchmentLight),
          greaterThanOrEqualTo(4.5)); // 6.64:1
    });
  });

  group('green type', () {
    test('the net-estate figure clears AA in dark', () {
      // bottleGreen (1.59:1) and even the prototype's dark --green (2.59:1) fail here.
      expect(_contrast(WasiatiColors.bottleGreen, WasiatiColors.nightSurface), lessThan(3));
      expect(_contrast(WasiatiColors.greenSoft, WasiatiColors.nightSurface), lessThan(3));
      expect(_contrast(WasiatiColors.darkTextMuted, WasiatiColors.nightSurface),
          greaterThanOrEqualTo(4.5)); // 6.89:1
    });

    test('the heir role chip reads in both themes', () {
      expect(_contrast(WasiatiColors.bottleGreen, WasiatiColors.greenTint), greaterThanOrEqualTo(4.5));
      final darkChip = _over(WasiatiColors.greenSoft.withValues(alpha: 0.25), WasiatiColors.nightRaised);
      expect(_contrast(WasiatiColors.greenTint, darkChip), greaterThanOrEqualTo(4.5));
    });
  });

  group('green type + highlighted boxes (tokens.greenInk / tokens.highlight)', () {
    // Owner report: "in dark mode any green fonts should be in white, so it's
    // readable — highlighted boxes in the main dashboard shouldn't be baby blue in
    // dark mode, make them dark green; watch out, I think it's connected to the
    // light mode's baby blue shading." It was: greenTint drove BOTH, hard-coded.

    test('greenInk clears AA on both themes\' card + raised surfaces', () {
      for (final night in [WasiatiColors.nightSurface, WasiatiColors.nightRaised]) {
        expect(_contrast(WasiatiTokens.dark.greenInk, night), greaterThanOrEqualTo(4.5)); // 12.19:1 / 10.90:1
      }
      for (final light in [WasiatiColors.parchmentLight, WasiatiColors.parchment]) {
        expect(_contrast(WasiatiTokens.light.greenInk, light), greaterThanOrEqualTo(4.5)); // 8.99:1 / 8.09:1
      }
    });

    test('greenInk reads ON the highlighted box it labels, in both themes', () {
      // The checklist row is greenInk type on a tokens.highlight fill. Both ends
      // move together or the row goes unreadable — which is exactly what happened
      // when only the fill was theme-aware.
      expect(_contrast(WasiatiTokens.dark.greenInk, WasiatiTokens.dark.highlight),
          greaterThanOrEqualTo(4.5)); // 11.43:1
      expect(_contrast(WasiatiTokens.light.greenInk, WasiatiTokens.light.highlight),
          greaterThanOrEqualTo(4.5)); // 7.94:1
    });

    test('light mode did NOT move — the trap in the report', () {
      // The whole point of splitting rather than re-tuning: greenTint is also the
      // light theme's primaryContainer, so darkening it to fix dark mode would have
      // recoloured light mode too. Pin both light ends to their shipped constants.
      expect(WasiatiTokens.light.highlight, WasiatiColors.greenTint);
      expect(WasiatiTokens.light.greenInk, WasiatiColors.bottleGreen);
    });

    test('the dark highlight is a dark GREEN, not a lightened tint', () {
      // "make them dark green". greenDeep must stay darker than the card it sits on
      // (a sunken highlight), and must not drift back up the scale toward greenTint.
      expect(WasiatiTokens.dark.highlight, WasiatiColors.greenDeep);
      expect(_contrast(WasiatiTokens.dark.highlight, WasiatiColors.nightSurface), lessThan(1.5)); // 1.08:1 — a quiet inset, not a second card
      expect(_contrast(WasiatiColors.greenTint, WasiatiColors.nightSurface), greaterThan(10)); // 12.36:1 — the "baby blue" glare that was there
    });

    test('regression: the inks that caused the bug still fail, so the token is load-bearing', () {
      // bottleGreen was hard-coded as the checklist label, the vault glyph, the
      // active admin tab. On a night card it is 1.59:1 — worse than the gold bug.
      expect(_contrast(WasiatiColors.bottleGreen, WasiatiColors.nightSurface), lessThan(2)); // 1.59:1
      expect(_contrast(WasiatiColors.greenDeep, WasiatiColors.nightSurface), lessThan(2)); // 1.08:1
      // ...and no point on the brand green scale rescues it, which is WHY the dark
      // end is the parchment ink rather than a lighter green.
      expect(_contrast(WasiatiColors.greenSoft, WasiatiColors.nightSurface), lessThan(3)); // 2.59:1
    });

    test('the OutlinedButton stopped painting its label in scheme.primary', () {
      // The one green the THEME (not a screen) was producing: OutlinedButton's
      // foreground/side were scheme.primary, which in dark is darkPrimaryButton.
      expect(_contrast(WasiatiColors.darkPrimaryButton, WasiatiColors.nightSurface), lessThan(3)); // 2.59:1
      expect(_contrast(WasiatiColors.darkPrimaryButton, WasiatiColors.nightBg), lessThan(3)); // 2.92:1 — the ring missed 1.4.11 too
      // Light is untouched: greenInk IS scheme.primary there.
      expect(WasiatiTokens.light.greenInk, WasiatiColors.bottleGreen);
    });
  });

  group('body text tokens', () {
    test('muted clears AA on both surfaces', () {
      expect(_contrast(WasiatiTokens.dark.muted, WasiatiColors.nightSurface), greaterThanOrEqualTo(4.5));
      expect(_contrast(WasiatiTokens.light.muted, WasiatiColors.parchmentLight), greaterThanOrEqualTo(4.5));
    });

    test('dark faint clears AA', () {
      expect(_contrast(WasiatiTokens.dark.faint, WasiatiColors.nightSurface), greaterThanOrEqualTo(4.5)); // 4.78:1
    });

    test('light faint clears AA — the caption tier the owner could not read', () {
      // This was called "light faint is short of AA — PRE-EXISTING, not this change". It
      // pinned 3.2:1 and called the real fix "too broad to move here (it would restyle
      // every screen)". The owner then reported light-mode text as unreadable, and the
      // measurement was the one already written down here: every caption, helper line and
      // field label in the light theme sat under the 4.5 body-text bar — 2.96:1 against
      // parchment at worst, not the 3.29:1 quoted, because the note only checked the
      // palest of the four light surfaces.
      //
      // Restyling every screen was the right size of change, because every screen was the
      // size of the bug.
      for (final surface in const [
        WasiatiColors.parchment,
        WasiatiColors.parchmentLight,
        WasiatiColors.parchmentDeep,
        WasiatiColors.greenTint,
      ]) {
        expect(_contrast(WasiatiTokens.light.faint, surface), greaterThanOrEqualTo(4.5),
            reason: 'captions must clear AA on EVERY light surface, not just the palest');
      }
    });

    test('the three light text tiers stay visibly distinct', () {
      // Raising faint to the AA floor lands it on #6A6556 — all but identical to muted's
      // old #6B6455. That passes the contrast bar while quietly collapsing a three-level
      // type hierarchy into two, so muted was darkened to keep the gap open.
      final primary = _contrast(WasiatiColors.onLight, WasiatiColors.parchment);
      final muted = _contrast(WasiatiTokens.light.muted, WasiatiColors.parchment);
      final faint = _contrast(WasiatiTokens.light.faint, WasiatiColors.parchment);

      expect(faint, greaterThanOrEqualTo(4.5));
      expect(muted, greaterThan(faint + 1.0), reason: 'muted must read as a step above faint');
      expect(primary, greaterThan(muted + 1.0), reason: 'primary must read as a step above muted');
    });
  });

  group('the record dot', () {
    test('record is its own red, not danger', () {
      // The prototype keeps them disjoint: the record button's dot is a literal
      // #C46B5C, while "Delete" ten lines on is var(--danger). The screen had
      // transcribed danger, which is the wrong semantic — capture is not
      // destruction — before it is a contrast question at all.
      expect(WasiatiColors.record, isNot(WasiatiColors.danger));
      expect(_contrast(WasiatiColors.record, WasiatiColors.danger), greaterThan(1.5)); // 1.80:1 — a different colour, not a rounding difference
    });

    test('the dot is under 3:1 on the button field — INHERITED from the prototype', () {
      // The dot lives inside a FilledButton, so its background is scheme.primary,
      // never a card. Measured there, the prototype's own hex misses 3:1 on both
      // ends. That is not a 1.4.11 failure: the button navigates, carries one
      // state, and its label fully specifies the action, so the dot is not
      // required to understand the control (the next test guards that premise).
      // Pinned because the numbers are easy to assume away — and because the
      // obvious "fix", lightening the button, would break the label below.
      expect(_contrast(WasiatiColors.record, WasiatiColors.bottleGreen), lessThan(3)); // 2.59:1
      expect(_contrast(WasiatiColors.record, WasiatiColors.darkPrimaryButton), lessThan(3)); // 1.58:1

      // Still worth the swap: danger was roughly half as separated on both fields.
      expect(_contrast(WasiatiColors.record, WasiatiColors.bottleGreen),
          greaterThan(_contrast(WasiatiColors.danger, WasiatiColors.bottleGreen))); // 2.59 vs 1.44
      expect(_contrast(WasiatiColors.record, WasiatiColors.darkPrimaryButton),
          greaterThan(_contrast(WasiatiColors.danger, WasiatiColors.darkPrimaryButton))); // 1.58 vs 1.14
    });

    test('the label carries the meaning, which is what exempts the dot', () {
      // 1.4.11 spares the sub-3:1 dot only because "Record video" already says it.
      // If either label pair drops under AA the exemption goes with it and the dot
      // becomes a real violation, so guard the claim the exemption rests on. The
      // dark pair clears by 0.15 — lightening darkPrimaryButton would sink it.
      expect(_contrast(WasiatiColors.onDark, WasiatiColors.bottleGreen), greaterThanOrEqualTo(4.5)); // 8.23:1
      expect(_contrast(WasiatiColors.darkText, WasiatiColors.darkPrimaryButton), greaterThanOrEqualTo(4.5)); // 4.65:1
    });

    test('record the dot is an indicator: no ink reads on it, so it carries no label', () {
      // The raw #C46B5C is exempt from the type bar because it is only ever a dot,
      // border or tint — nothing is read on it. Confirm no ink rescues it as a field,
      // which is WHY the stop button uses the deepened recordStopField, not this.
      expect(_contrast(WasiatiColors.parchmentLight, WasiatiColors.record), lessThan(4.5)); // 3.27:1 — the prototype's own pairing
      expect(_contrast(WasiatiColors.onDark, WasiatiColors.record), lessThan(4.5)); // 3.18:1
      expect(_contrast(WasiatiColors.inkNavy, WasiatiColors.record), lessThan(4.5)); // 4.19:1 — the darkest ink we have
    });

    test('recordStopField the stop button stays red AND its label clears AA', () {
      // Owner decision (DECISIONS §14 addendum): keep the prototype's red — a red stop
      // control is the universal recording convention — but make the label read. The
      // fill is the record red deepened until onDark clears the 4.5 bar. It is close to
      // danger in luminance (a warmer terracotta), which is harmless: the record screen
      // never shows danger, and a stop-square icon carries the affordance regardless.
      expect(_contrast(WasiatiColors.onDark, WasiatiColors.recordStopField), greaterThanOrEqualTo(4.5)); // 4.94:1 — the label reads
      expect(_contrast(WasiatiColors.recordStopField, WasiatiColors.record), lessThan(1.7)); // 1.55:1 — a deepening of the record red, not a new hue
    });
  });

  group('theme pill', () {
    test('the off track identifies the control on every field it is mounted on', () {
      // Rail: the prototype's own parchment veil. The knob's silhouette carries it
      // there (9.79:1), which is why the veil is allowed to stay a whisper.
      expect(_contrast(WasiatiColors.parchment, WasiatiColors.railGreen), greaterThan(3));

      // Light surfaces: the knob is parchment on parchment (1.11:1), so the track
      // has to clear 3:1 by itself — on the Settings card and the auth background.
      final veil = WasiatiColors.inkNavy.withValues(alpha: 0.54);
      for (final field in [WasiatiColors.parchmentLight, WasiatiColors.parchment]) {
        expect(_contrast(_over(veil, field), field), greaterThanOrEqualTo(3.0)); // 3.41:1 / 3.30:1
      }

      // Guard the reason the veil could not simply be transplanted.
      expect(
          _contrast(_over(WasiatiColors.parchment.withValues(alpha: 0.22), WasiatiColors.parchmentLight),
              WasiatiColors.parchmentLight),
          lessThan(1.1)); // 1.02:1 — invisible
    });

    test('the on track and its moon glyph read', () {
      expect(_contrast(WasiatiColors.goldDeepDark, WasiatiColors.nightSurface), greaterThan(3));
      expect(_contrast(WasiatiColors.inkNavy, WasiatiColors.parchment), greaterThanOrEqualTo(4.5));
    });
  });
}
