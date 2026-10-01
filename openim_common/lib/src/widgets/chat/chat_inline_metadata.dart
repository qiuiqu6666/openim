import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lay out the message at full width before fitting metadata on its last line.
class ChatInlineMetadata extends MultiChildRenderObjectWidget {
  ChatInlineMetadata(
      {super.key, required Widget content, required Widget metadata})
      : super(children: [content, metadata]);

  @override
  RenderObject createRenderObject(BuildContext context) => _InlineMetadata();
}

class _MetadataParentData extends ContainerBoxParentData<RenderBox> {}

class _InlineMetadata extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox,
            ContainerBoxParentData<RenderBox>>,
        RenderBoxContainerDefaultsMixin<RenderBox,
            ContainerBoxParentData<RenderBox>> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _MetadataParentData();
    }
  }

  @override
  void performLayout() {
    final content = firstChild!;
    final metadata = lastChild!;
    final loose = constraints.loosen();
    content.layout(loose, parentUsesSize: true);
    metadata.layout(loose, parentUsesSize: true);
    RenderParagraph? paragraph;
    void visit(RenderObject node) {
      if (node is RenderParagraph) paragraph = node;
      node.visitChildren(visit);
    }

    visit(content);
    double width = math.max(content.size.width, metadata.size.width);
    double y = content.size.height + 4;
    final text = paragraph;
    if (text != null && !text.didExceedMaxLines) {
      final plain = text.text.toPlainText();
      final boxes = text.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: plain.length));
      if (boxes.isNotEmpty && !plain.endsWith('\n')) {
        final bottom = boxes.map((b) => b.bottom).reduce(math.max);
        final last = boxes.where((b) => (b.bottom - bottom).abs() < 1);
        final right = last.map((b) => b.right).reduce(math.max);
        final top = last.map((b) => b.top).reduce(math.min);
        final offset = text.localToGlobal(Offset.zero, ancestor: content);
        final needed = offset.dx + right + 6 + metadata.size.width;
        if (needed <= constraints.maxWidth) {
          width = math.max(width, needed);
          y = offset.dy + top;
          y += math.max(0, bottom - top - metadata.size.height);
          // Lower the receipt slightly without consuming a separate text line.
          y += 4;
        }
      }
    }
    size = constraints.constrain(
        Size(width, math.max(content.size.height, y + metadata.size.height)));
    (content.parentData! as ContainerBoxParentData<RenderBox>).offset =
        Offset.zero;
    (metadata.parentData! as ContainerBoxParentData<RenderBox>).offset =
        Offset(size.width - metadata.size.width, y);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
