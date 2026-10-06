import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Marks the actual message bubble without changing its layout or lifecycle.
class ChatMessageContentAnchor extends SingleChildRenderObjectWidget {
  const ChatMessageContentAnchor({
    super.key,
    required this.messageID,
    required super.child,
  });

  final String messageID;

  @override
  RenderChatMessageContentAnchor createRenderObject(BuildContext context) =>
      RenderChatMessageContentAnchor(messageID: messageID);

  @override
  void updateRenderObject(
          BuildContext context, RenderChatMessageContentAnchor renderObject) =>
      renderObject.messageID = messageID;
}

class RenderChatMessageContentAnchor extends RenderProxyBox {
  RenderChatMessageContentAnchor({required String messageID})
      : _messageID = messageID;

  String _messageID;
  Rect _contentBounds = Rect.zero;
  String get messageID => _messageID;
  Rect get contentBounds => _contentBounds;

  set messageID(String value) {
    if (_messageID == value) return;
    _messageID = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    // Ancestors may inspect this marker during their layout, when directly
    // reading a deeper descendant's RenderBox.size is outside its scope.
    _contentBounds = Offset.zero & size;
  }
}
