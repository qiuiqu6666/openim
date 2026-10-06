import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chat_toolbox_tokens.dart';

/// A bounded vertical scroll keeps both rows usable at larger text scales.
class ChatToolboxGrid extends StatelessWidget {
  const ChatToolboxGrid({
    super.key,
    required this.page,
    required this.items,
    required this.labels,
  });

  final int page;
  final List<Widget Function(double width, double height)> items;
  final List<String> labels;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth =
              constraints.maxWidth + ChatToolboxTokens.panelPadding * 2;
          final spacing = math.max(
              0.0,
              (panelWidth -
                      ChatToolboxTokens.spacingCalculationSide * 2 -
                      ChatToolboxTokens.itemWidth * ChatToolboxTokens.columns) /
                  (ChatToolboxTokens.columns - 1));
          final itemWidth = math.min(
              ChatToolboxTokens.itemWidth,
              (constraints.maxWidth -
                      spacing * (ChatToolboxTokens.columns - 1)) /
                  ChatToolboxTokens.columns);
          final style = ChatToolboxTokens.labelStyle(context);
          var labelHeight = 0.0;
          for (final label in labels) {
            final painter = TextPainter(
              text: TextSpan(text: label, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
              ellipsis: '…',
            )..layout(maxWidth: itemWidth);
            labelHeight = math.max(labelHeight, painter.height);
            painter.dispose();
          }
          final itemHeight = math.max(
              ChatToolboxTokens.itemHeight,
              ChatToolboxTokens.iconSlotSize +
                  ChatToolboxTokens.labelGap +
                  labelHeight);
          return SingleChildScrollView(
            key: ValueKey('chat-toolbox-page-$page'),
            primary: false,
            physics: const ClampingScrollPhysics(),
            child: SizedBox(
              width: constraints.maxWidth,
              child: Wrap(
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.start,
                spacing: spacing,
                runSpacing: ChatToolboxTokens.rowGap,
                children: [
                  for (final item in items) item(itemWidth, itemHeight),
                ],
              ),
            ),
          );
        },
      );
}
