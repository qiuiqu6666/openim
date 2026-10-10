import 'package:flutter/cupertino.dart';
import '../utils/text/unicode_text.dart';

class TextWithMidEllipsis extends StatelessWidget {
  final String data;
  final TextStyle style;
  final TextAlign? textAlign;
  final TextDirection textDirection;
  final int endPartLength;

  const TextWithMidEllipsis(
    this.data, {
    Key? key,
    this.textAlign,
    this.style = const TextStyle(),
    this.endPartLength = 10,
  })  : textDirection = TextDirection.ltr,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraint) {
        if (constraint.maxWidth <= _textSize(data, style).width &&
            data.characters.length > endPartLength) {
          final endPart = graphemeSuffix(data, endPartLength);
          final leading =
              graphemePrefix(data, data.characters.length - endPartLength);
          return Row(
            children: [
              Flexible(
                child: Text(
                  leading,
                  style: style,
                  textAlign: textAlign,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textDirection: textDirection,
                ),
              ),
              Text(
                endPart,
                style: style,
                textDirection: textDirection,
                textAlign: textAlign,
              ),
            ],
          );
        }
        return Text(
          data,
          style: style,
          textAlign: textAlign,
          maxLines: 1,
          textDirection: textDirection,
        );
      },
    );
  }

  Size _textSize(String text, TextStyle style) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: style,
      ),
      maxLines: 1,
      textDirection: textDirection,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return textPainter.size;
  }
}

extension AppStringExtension on String {
  String get fixOverflowEllipsis => this;
}
