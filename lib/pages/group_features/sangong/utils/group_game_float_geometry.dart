// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// 群游戏浮窗默认锚点：右下角（与历史 `right:12 / bottom:120+inset` 对齐）。
Offset defaultGroupGameFloatOffset({
  required Size screenSize,
  required Size childSize,
  required double bottomInset,
  double right = 12,
  double bottom = 120,
}) {
  return Offset(
    screenSize.width - childSize.width - right,
    screenSize.height - childSize.height - bottom - bottomInset,
  );
}

/// 浮窗水平可吸附的左右边界（已含安全区与 edge）。
({double left, double right}) groupGameFloatHorizontalEdges({
  required Size screenSize,
  required Size childSize,
  required EdgeInsets viewPadding,
  double edge = 8,
}) {
  final left = viewPadding.left + edge;
  final right = math.max(
    left,
    screenSize.width - childSize.width - viewPadding.right - edge,
  );
  return (left: left, right: right);
}

/// 把浮窗左上角限制在安全区内，避免拖出屏幕。
Offset clampGroupGameFloatOffset({
  required Offset offset,
  required Size screenSize,
  required Size childSize,
  required EdgeInsets viewPadding,
  double edge = 8,
}) {
  final edges = groupGameFloatHorizontalEdges(
    screenSize: screenSize,
    childSize: childSize,
    viewPadding: viewPadding,
    edge: edge,
  );
  final minTop = viewPadding.top + edge;
  final maxTop = math.max(
    minTop,
    screenSize.height - childSize.height - viewPadding.bottom - edge,
  );
  return Offset(
    offset.dx.clamp(edges.left, edges.right),
    offset.dy.clamp(minTop, maxTop),
  );
}

/// 松手后水平吸边：以面板水平中心相对屏幕中线，靠左或靠右；纵轴保持。
Offset snapGroupGameFloatOffsetToHorizontalEdge({
  required Offset offset,
  required Size screenSize,
  required Size childSize,
  required EdgeInsets viewPadding,
  double edge = 8,
}) {
  final edges = groupGameFloatHorizontalEdges(
    screenSize: screenSize,
    childSize: childSize,
    viewPadding: viewPadding,
    edge: edge,
  );
  final midX = offset.dx + childSize.width / 2;
  final preferLeft = midX <= screenSize.width / 2;
  return clampGroupGameFloatOffset(
    offset: Offset(preferLeft ? edges.left : edges.right, offset.dy),
    screenSize: screenSize,
    childSize: childSize,
    viewPadding: viewPadding,
    edge: edge,
  );
}
