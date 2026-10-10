import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Entity offsets keep the SDK's UTF-16 units; display spans never split a
/// grapheme cluster. Invalid protocol ranges are ignored.
class ChatFormattedText extends StatelessWidget {
  const ChatFormattedText(
      {super.key, required this.text, required this.entities});
  final String text;
  final List<MessageEntity> entities;

  static List<InlineSpan> spans(
      String text, List<MessageEntity> entities, TextStyle base) {
    final graphemes = graphemeBoundaries(text);
    final valid = entities
        .where((e) =>
            e.offset != null &&
            e.length != null &&
            e.offset! >= 0 &&
            e.length! > 0 &&
            e.offset! + e.length! <= text.length)
        .take(200)
        .map((e) => (
              entity: e,
              range: graphemeSafeRange(text, e.offset!, e.offset! + e.length!,
                  boundaries: graphemes),
            ))
        .toList();
    final boundaries = <int>{0, text.length};
    for (final e in valid) {
      boundaries.add(e.range.start);
      boundaries.add(e.range.end);
    }
    final sorted = boundaries.toList()..sort();
    return [
      for (var i = 0; i < sorted.length - 1; i++)
        TextSpan(
            text: text.substring(sorted[i], sorted[i + 1]),
            style: _style(
                base,
                valid
                    .where((e) =>
                        e.range.start <= sorted[i] &&
                        e.range.end >= sorted[i + 1])
                    .map((e) => e.entity.type ?? '')
                    .toSet()))
    ];
  }

  static TextStyle _style(TextStyle base, Set<String> types) => base.copyWith(
        fontWeight: types.contains('bold') ? FontWeight.bold : null,
        fontStyle: types.contains('italic') ? FontStyle.italic : null,
        decoration: TextDecoration.combine([
          if (types.contains('underline')) TextDecoration.underline,
          if (types.contains('strikethrough')) TextDecoration.lineThrough,
        ]),
      );
  @override
  Widget build(BuildContext context) => Text.rich(
      TextSpan(children: spans(text, entities, Styles.ts_0C1C33_17sp)));
}
