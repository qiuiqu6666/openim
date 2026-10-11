import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../config.dart';
import '../utils/data_sp.dart';

/// An account-bound invalidation, never a replacement for SDK conversation data.
class ConversationRefreshRequest {
  ConversationRefreshRequest({
    required this.accountID,
    this.conversationID,
    this.sourceID,
    this.sessionType,
  })  : _imToken = DataSp.imToken,
        _chatToken = DataSp.chatToken,
        _server = Config.imApiUrl;

  final String accountID;
  final String? conversationID, sourceID;
  final int? sessionType;
  final String? _imToken, _chatToken;
  final String _server;

  bool get isCurrent =>
      accountID.isNotEmpty &&
      accountID == OpenIM.iMManager.userID &&
      _imToken == DataSp.imToken &&
      _chatToken == DataSp.chatToken &&
      _server == Config.imApiUrl;

  String get key => conversationID ?? '$sessionType:$sourceID';

  static ConversationRefreshRequest? forMessage(Message message) {
    if (message.contentType == MessageType.typing ||
        message.customElem?.description == 'assistantStream') {
      return null;
    }
    final owner = OpenIM.iMManager.userID;
    final type = message.sessionType;
    String? source;
    if (type == ConversationType.single) {
      if (message.sendID == owner) {
        source = message.recvID;
      } else if (message.recvID == owner) {
        source = message.sendID;
      }
    } else if (type ==
            ConversationType.group || // ignore: deprecated_member_use
        type == ConversationType.superGroup) {
      source = message.groupID;
    }
    if (source == null || source.isEmpty) return null;
    return ConversationRefreshRequest(
        accountID: owner, sourceID: source, sessionType: type);
  }
}

/// Ordinary sends and locally persisted call records share this non-replaying
/// signal. List controllers own subscriptions, batching and SDK reads.
abstract final class ConversationRefreshEvents {
  static final _changes =
      StreamController<ConversationRefreshRequest>.broadcast();
  static Stream<ConversationRefreshRequest> get changes => _changes.stream;

  static void publish(ConversationRefreshRequest request) {
    if (request.isCurrent) _changes.add(request);
  }
}
