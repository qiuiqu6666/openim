import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// SDK text keeps its paragraph breaks for assistant Markdown and copying.
/// The shared conversation preview formatter intentionally flattens newlines.
String aiOpenimMessageText(Message message) => switch (message.contentType) {
      MessageType.text => message.textElem?.content ?? '',
      MessageType.atText => message.atTextElem?.text ?? '',
      MessageType.quote => message.quoteElem?.text ?? '',
      MessageType.advancedText => message.advancedTextElem?.text ?? '',
      _ => IMUtils.parseMsg(message),
    };
