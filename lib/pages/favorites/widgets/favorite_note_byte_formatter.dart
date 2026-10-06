import 'dart:convert';

import 'package:flutter/services.dart';

/// Enforces the API's UTF-8 limit without cutting a cloud note or grapheme.
/// Active IME text remains editable; the editor also checks bytes before save.
class FavoriteNoteByteFormatter extends TextInputFormatter {
  const FavoriteNoteByteFormatter();

  static const maxBytes = 64 * 1024;
  static int byteLength(String text) => utf8.encode(text).length;
  static bool canSave(String text) => byteLength(text) <= maxBytes;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final size = byteLength(newValue.text);
    if (size <= maxBytes || size < byteLength(oldValue.text)) return newValue;
    return oldValue;
  }
}
