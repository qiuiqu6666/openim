import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// The API counts Unicode scalars. Keep composed characters intact when
/// limiting the keyword, and let an active IME composition finish normally.
class FavoriteSearchFormatter extends TextInputFormatter {
  const FavoriteSearchFormatter();
  static const maxScalars = 64;
  static String limit(String text) {
    var count = 0;
    final value = StringBuffer();
    for (final character in text.characters) {
      final size = character.runes.length;
      if (count + size > maxScalars) break;
      value.write(character);
      count += size;
    }
    return value.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final text = limit(newValue.text);
    if (text == newValue.text) return newValue;
    return TextEditingValue(
        text: text,
        selection: TextSelection(
            baseOffset: newValue.selection.baseOffset.clamp(0, text.length),
            extentOffset:
                newValue.selection.extentOffset.clamp(0, text.length)));
  }
}
