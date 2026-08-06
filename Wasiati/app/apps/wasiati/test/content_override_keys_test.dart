import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/content/application/content_providers.dart';

/// The admin Content editor and the app must agree on which strings are overridable.
///
/// They did not. The editor took a FREE-FORM key, saved whatever was typed, and answered
/// 200 — but the app renders an override only where a surface opted in by calling
/// overrideText(). Exactly one string had (sealWry), out of ~1150. So an owner could
/// correct any other string, watch it save, and have the old text keep rendering forever,
/// with nothing anywhere reporting the mismatch. ContentService advertises this system as
/// the way to fix "a string — including the legal disclaimer" without an app release,
/// which is the case where silence is worst.
///
/// The editor now offers `overridableKeys` instead of free text. That only stays true if
/// the list and the call sites move together, which is what this pins: the list is the
/// product's promise, and a promise nothing renders is the bug being fixed.
void main() {
  final libDir = Directory('lib');

  /// Every key passed to overrideText anywhere in lib/.
  Set<String> wiredKeys() {
    final pattern = RegExp(r"""overrideText\(\s*ref\s*,\s*key:\s*'([^']+)'""");
    final found = <String>{};
    for (final f in libDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      // The doc comment on overrideText itself carries an example call.
      if (f.path.endsWith('content_providers.dart')) continue;
      for (final m in pattern.allMatches(f.readAsStringSync())) {
        found.add(m.group(1)!);
      }
    }
    return found;
  }

  test('every key the editor offers is actually rendered by a screen', () {
    final wired = wiredKeys();
    final offered = overridableKeys.toSet();
    final deadOnArrival = offered.difference(wired);

    expect(deadOnArrival, isEmpty,
        reason: 'These keys are offered in the admin Content editor but no screen calls '
            'overrideText for them, so publishing one changes nothing a user sees — the '
            'exact silent no-op this list exists to prevent: $deadOnArrival');
  });

  test('every key a screen renders is offered in the editor', () {
    final wired = wiredKeys();
    final offered = overridableKeys.toSet();
    final unreachable = wired.difference(offered);

    expect(unreachable, isEmpty,
        reason: 'These strings are wired for override but the editor will not offer them, '
            'so the owner cannot correct them and the wiring is decoration: $unreachable');
  });

  test('the legal disclaimer is overridable — the case the system exists for', () {
    // ContentService names this one explicitly. It gates sealing, so shipping a stale
    // version of it is a legal problem, not a cosmetic one.
    expect(overridableKeys, contains('rsReviewedConfirm'));
    expect(wiredKeys(), contains('rsReviewedConfirm'),
        reason: 'listed but not wired would mean an admin can publish a disclaimer '
            'correction that never reaches a single user');
  });

  test('the list is not empty', () {
    // A guard against "fixing" a future drift failure by emptying the list.
    expect(overridableKeys, isNotEmpty);
  });
}
