import 'package:flutter/material.dart';

/// Gives long decimal numbers wrap opportunities without changing their
/// numeric characters or their spoken value.
class WalletRecordAmountText extends StatelessWidget {
  const WalletRecordAmountText({
    super.key,
    required this.value,
    required this.style,
    this.textKey,
    this.textAlign = TextAlign.end,
  });

  final String value;
  final TextStyle style;
  final Key? textKey;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(
                text: value,
                style: DefaultTextStyle.of(context).style.merge(style)),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final wrap = painter.width > constraints.maxWidth;
          painter.dispose();
          final display = wrap
              ? value.replaceAllMapped(
                  RegExp(r'([0-9])(?=[0-9])'), (match) => '${match[1]}\u200B')
              : value;
          return Text(display,
              key: textKey,
              semanticsLabel: value,
              style: style,
              textAlign: textAlign);
        },
      );
}
