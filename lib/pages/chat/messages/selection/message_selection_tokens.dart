import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Geometry from 99chat's chat host app bar, radio button and multi-select panel.
abstract final class MessageSelectionTokens {
  static const indicatorSize = 22.0;
  static const indicatorBorder = 1.5;
  static const checkSize = 11.0;
  static const indicatorSlot = 48.0;
  static const toolbarSide = 88.0;
  static const titleSize = 17.0;
  static const barHeight = 48.0;
  static const iconSize = 20.0;
  static const labelSize = 11.0;
  static const labelGap = 2.0;
  static const dividerWidth = .5;
  static const forwardIcon =
      'lib/pages/chat/messages/selection/assets/forward_99chat.png';
  static const mergeIcon =
      'lib/pages/chat/messages/selection/assets/merge_forward_99chat.png';
  static const deleteIcon =
      'lib/pages/chat/messages/selection/assets/delete_99chat.png';

  static Color border(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
  static Color foreground(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  static Color unselected(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.transparent
          : AppTokens.surfaceLight;
}
