import 'package:flutter/services.dart';

import '../../../utils/text/unicode_text.dart';

/// Panel edits are explicit committed actions. IME edits remain owned by
/// EditableText; selection and composing offsets are UTF-16, never counts.
TextEditingValue insertChatText(TextEditingValue value, String inserted) {
  final selection = value.selection;
  final text = value.text;
  final start = selection.isValid ? selection.start : text.length;
  final end = selection.isValid ? selection.end : text.length;
  final range = start == end
      ? (
          start: graphemeBoundaryAfter(text, start),
          end: graphemeBoundaryAfter(text, start)
        )
      : graphemeSafeRange(text, start, end);
  final edited = text.replaceRange(range.start, range.end, inserted);
  return TextEditingValue(
    text: edited,
    // Adjacent runs can form a new cluster after replacement (for example,
    // two regional indicators). Align against the resulting text as well.
    selection: TextSelection.collapsed(
        offset: graphemeBoundaryAfter(edited, range.start + inserted.length)),
  );
}

TextEditingValue deleteChatTextBackward(TextEditingValue value) {
  if (value.text.isEmpty) return value;
  final selection = value.selection;
  final text = value.text;
  final start =
      (selection.isValid ? selection.start : text.length).clamp(0, text.length);
  final end =
      (selection.isValid ? selection.end : text.length).clamp(0, text.length);
  if (start == 0 && end == 0) return value;
  final range = start == end
      ? (
          start: graphemeBoundaryBefore(text, start - 1),
          end: graphemeBoundaryAfter(text, end)
        )
      : graphemeSafeRange(text, start, end);
  final edited = text.replaceRange(range.start, range.end, '');
  return TextEditingValue(
    text: edited,
    selection: TextSelection.collapsed(
        offset: graphemeBoundaryAfter(edited, range.start)),
  );
}
