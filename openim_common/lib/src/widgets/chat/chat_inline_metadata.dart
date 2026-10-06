import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import '../../res/app_tokens.dart';

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
    final paragraphs = <RenderParagraph>[];
    void visit(RenderObject node) {
      if (node is RenderParagraph) paragraphs.add(node);
      node.visitChildren(visit);
    }

    visit(content);
    double width = math.max(content.size.width, metadata.size.width);
    double y = content.size.height + ChatBubbleTokens.metadataVerticalGap;
    // Multiple paragraphs have independent line metrics; leave their footer
    // below the whole body rather than treating the last paragraph as all text.
    final text = paragraphs.length == 1 ? paragraphs.single : null;
    if (text != null && !text.didExceedMaxLines) {
      final plain = text.text.toPlainText();
      // Tight boxes follow individual font metrics. A CJK fallback glyph may
      // descend below adjacent digits on the same line, so grouping tight
      // boxes by bottom would omit those digits from the trailing width.
      // Line-height boxes give every run on one line the same vertical bounds.
      final boxes = text.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: plain.length),
        boxHeightStyle: BoxHeightStyle.max,
      );
      if (boxes.isNotEmpty &&
          !plain.endsWith('\n') &&
          boxes.every((box) => box.direction == TextDirection.ltr)) {
        final bottom = boxes.map((b) => b.bottom).reduce(math.max);
        final last = boxes.where((b) => (b.bottom - bottom).abs() < 1);
        final right = last.map((b) => b.right).reduce(math.max);
        final top = last.map((b) => b.top).reduce(math.min);
        final offset = text.localToGlobal(Offset.zero, ancestor: content);
        final needed = offset.dx +
            right +
            ChatBubbleTokens.metadataHorizontalGap +
            metadata.size.width;
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
