import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

enum ChatMessageSource { live, offline, onlineOnly, local }

/// A route owns its subscription; another chat cannot replace its receiver.
class ChatMessageEvent {
  const ChatMessageEvent(this.message, this.source);
  final Message message;
  final ChatMessageSource source;
}
