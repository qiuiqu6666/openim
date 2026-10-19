import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../protocol/ai_image_turn.dart';

/// SDK text keeps its paragraph breaks for assistant Markdown and copying.
/// The shared conversation preview formatter intentionally flattens newlines.
String aiOpenimMessageText(Message message) => switch (message.contentType) {
      MessageType.text => message.textElem?.content ?? '',
      MessageType.atText => message.atTextElem?.text ?? '',
      MessageType.quote => message.quoteElem?.text ?? '',
      MessageType.advancedText => message.advancedTextElem?.text ?? '',
      MessageType.custom
          when message.customElem?.description == AiImageTurn.description =>
        AiImageTurn.parse(message.customElem?.data)?.text ??
            IMUtils.parseMsg(message),
      _ => IMUtils.parseMsg(message),
    };
