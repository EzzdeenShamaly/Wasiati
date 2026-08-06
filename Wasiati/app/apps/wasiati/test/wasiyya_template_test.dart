// "Words for my family" template seeding (create-will step 5).
//
// The owner reported Enter-to-seed and Delete-to-clear both dead. These drive the
// formatter the way EditableText does — (oldValue, newValue) as the platform reports
// each edit — so they pin the behaviour the old onChanged newline test could not
// deliver: it never saw deletions at all, and its controller rewrite raced the value
// already in flight to the platform text buffer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/wills/presentation/wasiyya_template_formatter.dart';

const _tmpl = 'Bismillah.\n\nThis is what I enjoin upon my family…';

TextEditingValue _v(String text, [int? offset]) =>
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset ?? text.length));

/// One edit, as EditableText would apply it.
TextEditingValue edit(String from, String to) =>
    const WasiyyaTemplateFormatter(_tmpl).formatEditUpdate(_v(from), _v(to));

void main() {
  group('Enter on a blank field seeds the classic wasiyya', () {
    test('empty field + Enter -> the template, caret at the end', () {
      final r = edit('', '\n');
      expect(r.text, _tmpl);
      expect(r.selection.baseOffset, _tmpl.length);
    });

    test('whitespace-only field + Enter -> the template (prototype: !msg.trim())', () {
      expect(edit('   ', '   \n').text, _tmpl);
      expect(edit('\n', '\n\n').text, _tmpl);
    });

    test('typing an ordinary character on a blank field does NOT seed', () {
      expect(edit('', 'A').text, 'A');
    });

    test('Enter inside real words is left alone — the owner is writing', () {
      expect(edit('Dear family', 'Dear family\n').text, 'Dear family\n');
    });
  });

  group('Delete/clear on the untouched template clears it', () {
    test('Backspace at the end -> empty', () {
      final r = edit(_tmpl, _tmpl.substring(0, _tmpl.length - 1));
      expect(r.text, '');
      expect(r.selection.baseOffset, 0);
    });

    test('deleting a character from the middle also clears the whole template', () {
      // Matches the prototype: any Backspace/Delete while msg === tmpl wipes it.
      final r = edit(_tmpl, _tmpl.replaceFirst('B', ''));
      expect(r.text, '');
    });

    test('select-all + delete -> empty', () {
      expect(edit(_tmpl, '').text, '');
    });

    test('an edited template is the owner\'s words — deleting trims, never wipes', () {
      const mine = '$_tmpl and one more thing';
      final r = edit(mine, mine.substring(0, mine.length - 1));
      expect(r.text, mine.substring(0, mine.length - 1));
    });

    test('appending to the template is passed straight through', () {
      const longer = '$_tmpl!';
      expect(edit(_tmpl, longer).text, longer);
    });
  });

  group('seed then clear then seed again', () {
    test('the field round-trips', () {
      final seeded = edit('', '\n');
      expect(seeded.text, _tmpl);
      final cleared = edit(seeded.text, seeded.text.substring(0, seeded.text.length - 1));
      expect(cleared.text, '');
      expect(edit(cleared.text, '\n').text, _tmpl, reason: 'a cleared field seeds again');
    });
  });

  test('the template follows the locale it was built with', () {
    const ar = WasiyyaTemplateFormatter('بسم الله الرحمن الرحيم');
    expect(ar.formatEditUpdate(_v(''), _v('\n')).text, 'بسم الله الرحمن الرحيم');
  });

  // The unit tests above call the formatter directly. This one drives a real
  // multi-line TextField wired exactly as step 5 wires it, so it also proves the
  // formatter is actually reached on the live text-input path — the part the old
  // onChanged implementation got wrong.
  group('in a real TextField (as step 5 builds it)', () {
    Future<TextEditingController> pump(WidgetTester tester) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: c,
            maxLines: 10,
            minLines: 7,
            maxLength: 5000,
            inputFormatters: const [WasiyyaTemplateFormatter(_tmpl)],
            decoration: const InputDecoration(hintText: 'placeholder'),
          ),
        ),
      ));
      return c;
    }

    testWidgets('Enter on the empty field seeds the template', (tester) async {
      final c = await pump(tester);
      await tester.enterText(find.byType(TextField), '\n');
      await tester.pump();
      expect(c.text, _tmpl);
    });

    testWidgets('Backspace on the seeded template clears it back to the placeholder', (tester) async {
      final c = await pump(tester);
      await tester.enterText(find.byType(TextField), '\n');
      await tester.pump();
      expect(c.text, _tmpl);

      await tester.enterText(find.byType(TextField), _tmpl.substring(0, _tmpl.length - 1));
      await tester.pump();
      expect(c.text, '');
      expect(find.text('placeholder'), findsOneWidget, reason: 'an empty field shows its hint again');
    });

    testWidgets('the owner\'s own words survive editing', (tester) async {
      final c = await pump(tester);
      await tester.enterText(find.byType(TextField), 'My children,');
      await tester.pump();
      expect(c.text, 'My children,');
      await tester.enterText(find.byType(TextField), 'My children');
      await tester.pump();
      expect(c.text, 'My children');
    });
  });
}
