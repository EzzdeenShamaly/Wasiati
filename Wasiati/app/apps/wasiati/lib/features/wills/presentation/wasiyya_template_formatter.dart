import 'package:flutter/services.dart';

/// "Words for my family" (create-flow step 5): pressing Enter on a blank field seeds
/// the classic wasiyya template, and Delete/Backspace on the untouched template clears
/// it again — the prototype's `msgKey` handler, which preventDefault()s the keystroke
/// and swaps the text.
///
/// This runs as an input FORMATTER rather than an onChanged or key hook on purpose:
///
///  * The original `if (v == '\n')` test inside `TextField.onChanged` rewrote
///    `controller.text` from inside EditableText's own change notification, so the
///    swap raced the value already on its way to the platform text buffer — the seed
///    was silently dropped and the field kept the bare newline. A formatter rewrites
///    the value BEFORE it is committed or synced to the engine, so there is nothing to
///    race, and it is IME/autocorrect-safe.
///  * A formatter also sees DELETIONS, which no onChanged newline test can detect at
///    all — that is why clearing the template never worked.
///  * A parent `Focus(onKeyEvent:)` would not help either: key events reach the text
///    field's own focus node first, so the newline is already inserted by the time an
///    ancestor sees the event. There is no preventDefault to be had there.
class WasiyyaTemplateFormatter extends TextInputFormatter {
  /// The classic wasiyya text (l10n key `cwWordsDefault`, so it follows the locale).
  final String template;
  const WasiyyaTemplateFormatter(this.template);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final grew = newValue.text.length > oldValue.text.length;
    // Enter on an empty — or whitespace-only, per the prototype's `!msg.trim()` —
    // field seeds the template and puts the caret at the end.
    if (grew && oldValue.text.trim().isEmpty && newValue.text.trim().isEmpty && newValue.text.contains('\n')) {
      return TextEditingValue(text: template, selection: TextSelection.collapsed(offset: template.length));
    }
    // Any deletion off the pristine template clears the whole thing, so the field goes
    // back to showing its placeholder and Enter can seed it again. Once the owner has
    // edited the template it is their words, and this no longer fires.
    if (!grew && newValue.text.length < oldValue.text.length && oldValue.text == template) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }
    return newValue;
  }
}
