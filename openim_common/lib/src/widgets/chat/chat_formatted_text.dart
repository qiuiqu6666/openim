import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Entity offsets use the SDK's string offsets. Invalid ranges are ignored.
class ChatFormattedText extends StatelessWidget {
  const ChatFormattedText(
      {super.key, required this.text, required this.entities});
  final String text;
  final List<MessageEntity> entities;

  static List<InlineSpan> spans(
      String text, List<MessageEntity> entities, TextStyle base) {
    bool boundary(int index) =>
        index <= 0 ||
        index >= text.length ||
        !(text.codeUnitAt(index) >= 0xDC00 &&
            text.codeUnitAt(index) <= 0xDFFF &&
            text.codeUnitAt(index - 1) >= 0xD800 &&
            text.codeUnitAt(index - 1) <= 0xDBFF);
    final valid = entities
        .where((e) =>
            e.offset != null &&
            e.length != null &&
            e.offset! >= 0 &&
            e.length! > 0 &&
            e.offset! + e.length! <= text.length &&
            boundary(e.offset!) &&
            boundary(e.offset! + e.length!))
        .take(200)
        .toList();
    final boundaries = <int>{0, text.length};
    for (final e in valid) {
      boundaries.add(e.offset!);
      boundaries.add(e.offset! + e.length!);
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
                        e.offset! <= sorted[i] &&
                        e.offset! + e.length! >= sorted[i + 1])
                    .map((e) => e.type ?? '')
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
