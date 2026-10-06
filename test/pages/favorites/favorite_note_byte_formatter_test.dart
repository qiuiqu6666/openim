import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/favorites/widgets/favorite_note_byte_formatter.dart';

void main() {
  test(
      'UTF-8 limits reject an entire oversized insertion without splitting emoji',
      () {
    const formatter = FavoriteNoteByteFormatter();
    final old = TextEditingValue(text: '${'中' * 21835}👨‍👩‍👧‍👦');
    final inserted = old.copyWith(text: '${old.text}👨‍👩‍👧‍👦');
    expect(FavoriteNoteByteFormatter.byteLength(old.text),
        lessThanOrEqualTo(65536));
    expect(formatter.formatEditUpdate(old, inserted), old);
    expect(FavoriteNoteByteFormatter.canSave(inserted.text), isFalse);
  });

  test(
      'a server note remains intact and an already oversized note can be reduced',
      () {
    const formatter = FavoriteNoteByteFormatter();
    final old = TextEditingValue(text: '中' * 22000);
    final shorter = old.copyWith(text: '中' * 21999);
    expect(formatter.formatEditUpdate(old, shorter), shorter);
    final longCloudNote = TextEditingValue(text: '文' * 5000);
    final addition = longCloudNote.copyWith(text: '${longCloudNote.text}🙂');
    expect(formatter.formatEditUpdate(longCloudNote, addition), addition);
  });
}
