import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:openim_common/openim_common.dart';

import 'message_selection_tokens.dart';

/// The message and indicator keep fixed child slots across selection changes.
class MessageSelectionLayout extends MultiChildRenderObjectWidget {
  MessageSelectionLayout({
    super.key,
    required this.messageID,
    required this.selecting,
    required Widget child,
    required Widget indicator,
  }) : super(children: [child, indicator]);

  final String messageID;
  final bool selecting;

  @override
  RenderMessageSelectionLayout createRenderObject(BuildContext context) =>
      RenderMessageSelectionLayout(messageID: messageID, selecting: selecting);

  @override
  void updateRenderObject(
      BuildContext context, RenderMessageSelectionLayout renderObject) {
    renderObject
      ..messageID = messageID
      ..selecting = selecting;
  }
}

class _SelectionParentData extends ContainerBoxParentData<RenderBox> {}

/// Measures the bubble in the same layout pass that positions its indicator.
class RenderMessageSelectionLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SelectionParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SelectionParentData> {
  RenderMessageSelectionLayout({
    required String messageID,
    required bool selecting,
  })  : _messageID = messageID,
        _selecting = selecting;

  String _messageID;
  bool _selecting;
  Rect? _bubbleInContent;

  String get messageID => _messageID;
  set messageID(String value) {
    if (_messageID == value) return;
    _messageID = value;
    _bubbleInContent = null;
    markNeedsLayout();
  }

  bool get selecting => _selecting;
  set selecting(bool value) {
    if (_selecting == value) return;
    _selecting = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  Rect get globalRowBounds => attached && hasSize
      ? MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size)
      : Rect.zero;

  Rect? get globalBubbleBounds {
    final bubble = _bubbleInContent;
    final content = firstChild;
    if (!attached || !hasSize || bubble == null || content == null) return null;
    final offset = (content.parentData! as _SelectionParentData).offset;
    return MatrixUtils.transformRect(
        getTransformTo(null), bubble.shift(offset));
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SelectionParentData) {
      child.parentData = _SelectionParentData();
    }
  }

  double _slot(BoxConstraints constraints) => selecting
      ? math.min(MessageSelectionTokens.indicatorSlot, constraints.maxWidth)
      : 0;

  BoxConstraints _contentConstraints(BoxConstraints constraints) {
    final width = math.max(0.0, constraints.maxWidth - _slot(constraints));
    return BoxConstraints(
      minWidth: constraints.hasBoundedWidth ? width : 0,
      maxWidth: width,
      maxHeight: constraints.maxHeight,
    );
  }

  BoxConstraints _indicatorConstraints(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: math.min(
            MessageSelectionTokens.indicatorSize,
            selecting
                ? _slot(constraints)
                : MessageSelectionTokens.indicatorSize),
        height: math.min(
            MessageSelectionTokens.indicatorSize, constraints.maxHeight),
      );

  Size _rowSize(BoxConstraints constraints, Size content, Size indicator) =>
      constraints.constrain(Size(
        content.width + _slot(constraints),
        selecting ? math.max(content.height, indicator.height) : content.height,
      ));

  @override
  Size computeDryLayout(BoxConstraints constraints) => _rowSize(
        constraints,
        firstChild!.getDryLayout(_contentConstraints(constraints)),
        lastChild!.getDryLayout(_indicatorConstraints(constraints)),
      );

  @override
  void performLayout() {
    final content = firstChild!;
    final indicator = lastChild!;
    content.layout(_contentConstraints(constraints), parentUsesSize: true);
    indicator.layout(_indicatorConstraints(constraints), parentUsesSize: true);
    size = _rowSize(constraints, content.size, indicator.size);
    final slot = _slot(constraints);
    (content.parentData! as _SelectionParentData).offset = Offset(slot, 0);

    RenderChatMessageContentAnchor? anchor;
    void findAnchor(RenderObject node) {
      if (anchor != null) return;
      if (node is RenderChatMessageContentAnchor &&
          node.messageID == messageID &&
          node.hasSize) {
        anchor = node;
        return;
      }
      node.visitChildren(findAnchor);
    }

    findAnchor(content);
    final bubble = anchor;
    _bubbleInContent = bubble == null
        ? null
        : MatrixUtils.transformRect(
            bubble.getTransformTo(content), bubble.contentBounds);
    final center = _bubbleInContent?.center.dy ?? content.size.height / 2;
    (indicator.parentData! as _SelectionParentData).offset = Offset(
        (slot - indicator.size.width) / 2, center - indicator.size.height / 2);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final content = firstChild!;
    context.paintChild(
        content, offset + (content.parentData! as _SelectionParentData).offset);
    if (selecting) {
      final indicator = lastChild!;
      context.paintChild(indicator,
          offset + (indicator.parentData! as _SelectionParentData).offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    bool hit(RenderBox child) => result.addWithPaintOffset(
          offset: (child.parentData! as _SelectionParentData).offset,
          position: position,
          hitTest: (result, position) =>
              child.hitTest(result, position: position),
        );
    return (selecting && hit(lastChild!)) || hit(firstChild!);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitor(firstChild!);
    if (selecting) visitor(lastChild!);
  }
}
