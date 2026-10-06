import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/favorites/widgets/favorite_search_formatter.dart';

void main() {
  test('keyword limits match 64 API scalars without splitting composed emoji',
      () {
    const formatter = FavoriteSearchFormatter();
    final input = List.filled(30, '👨‍👩‍👧‍👦').join();
    final edited = formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
            text: input,
            selection: TextSelection.collapsed(offset: input.length)));
    expect(edited.text.runes.length, lessThanOrEqualTo(64));
    expect(edited.text, List.filled(9, '👨‍👩‍👧‍👦').join());
    expect(edited.selection.extentOffset, edited.text.length);
  });
  test('IME draft remains intact while its submitted query is bounded', () {
    const formatter = FavoriteSearchFormatter();
    final input = List.filled(65, '字').join();
    final editing = TextEditingValue(
        text: input,
        composing: const TextRange(start: 64, end: 65),
        selection: const TextSelection.collapsed(offset: 65));
    expect(
        formatter.formatEditUpdate(TextEditingValue.empty, editing), editing);
    expect(FavoriteSearchFormatter.limit(editing.text).runes.length, 64);
    expect(
        formatter
            .formatEditUpdate(
                editing, editing.copyWith(composing: TextRange.empty))
            .text
            .runes
            .length,
        64);
  });
}
