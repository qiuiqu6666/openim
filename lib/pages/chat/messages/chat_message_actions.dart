import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

typedef LocalMessageDeletion = Future<void> Function({
  required String conversationID,
  required String clientMsgID,
});

/// Message menu policies and SDK deletion/revocation.
class ChatMessageActions {
  ChatMessageActions({
    required String Function() conversationID,
    required void Function(String) removeMessage,
    required bool Function() isClosed,
    LocalMessageDeletion? deleteFromLocalStorage,
    void Function(String)? showToast,
  })  : _conversationID = conversationID,
        _removeMessageByID = removeMessage,
        _isClosed = isClosed,
        _deleteFromLocalStorage = deleteFromLocalStorage ?? _sdkDelete,
        _showToast = showToast ?? ((text) => IMViews.showToast(text));
  final String Function() _conversationID;
  final void Function(String) _removeMessageByID;
  final bool Function() _isClosed;
  final LocalMessageDeletion _deleteFromLocalStorage;
  final void Function(String) _showToast;

  static Future<void> _sdkDelete(
      {required String conversationID, required String clientMsgID}) async {
    await OpenIM.iMManager.messageManager.deleteMessageFromLocalStorage(
        conversationID: conversationID, clientMsgID: clientMsgID);
  }

  bool _isFundMessage(Message message) =>
      message.contentType == MessageType.custom &&
      FundMessageData.tryParse(message.customElem?.data) != null;

  bool canRevoke(Message message) {
    // Recalling an IM record cannot cancel a posted funds order. Preserve the
    // server-created financial card so recall never suggests a refund.
    if (_isFundMessage(message)) return false;
    final sentAt = message.sendTime;
    return message.sendID == OpenIM.iMManager.userID &&
        message.status == MessageStatus.succeeded &&
        sentAt != null &&
        DateTime.now().millisecondsSinceEpoch - sentAt <
            const Duration(minutes: 2).inMilliseconds;
  }

  Future<void> revokeMessage(Message message) async {
    final clientMsgID = message.clientMsgID;
    if (clientMsgID == null || !canRevoke(message)) return;
    try {
      await OpenIM.iMManager.messageManager.revokeMessage(
        conversationID: _conversationID(),
        clientMsgID: clientMsgID,
      );
      if (!_isClosed()) _removeMessageByID(clientMsgID);
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  bool canForward(Message message) =>
      message.status == MessageStatus.succeeded &&
      message.attachedInfoElem?.isPrivateChat != true &&
      [
        MessageType.text,
        MessageType.atText,
        MessageType.advancedText,
        MessageType.picture,
        MessageType.video,
        MessageType.voice,
        MessageType.file,
        MessageType.card,
        MessageType.location,
        MessageType.customFace,
        MessageType.merger,
        MessageType.quote
      ].contains(message.contentType);

  Future<void> deleteMessage(Message message) async {
    final clientMsgID = message.clientMsgID;
    if (clientMsgID == null) return;
    try {
      await OpenIM.iMManager.messageManager.deleteMessageFromLocalStorage(
        conversationID: _conversationID(),
        clientMsgID: clientMsgID,
      );
      if (!_isClosed()) _removeMessageByID(clientMsgID);
    } catch (error) {
      IMViews.showToast(error.toString());
    }
  }

  /// Local deletion is independent of forwarding policy. Preserve financial
  /// cards, report partial failures once, and retain the successful removals.
  Future<bool> deleteMessages(List<Message> selection) async {
    if (_isClosed() || selection.isEmpty) return false;
    final messages = List<Message>.of(selection);
    final conversationID = _conversationID();
    bool current() => !_isClosed() && _conversationID() == conversationID;
    var failed = false, fundsBlocked = false;
    final visited = <String>{};
    for (final message in messages) {
      if (!current()) return false;
      if (_isFundMessage(message)) {
        fundsBlocked = true;
        continue;
      }
      final clientMsgID = message.clientMsgID;
      if (clientMsgID == null || clientMsgID.trim().isEmpty) {
        failed = true;
        continue;
      }
      if (!visited.add(clientMsgID)) continue;
      try {
        if (!current()) return false;
        await _deleteFromLocalStorage(
            conversationID: conversationID, clientMsgID: clientMsgID);
        if (!current()) return false;
        _removeMessageByID(clientMsgID);
      } catch (_) {
        if (!current()) return false;
        failed = true;
      }
    }
    if (!current()) return false;
    if (failed || fundsBlocked) {
      _showToast((fundsBlocked
              ? 'chatSelectionDeleteBlocked'
              : 'chatSelectionDeleteFailed')
          .tr);
      return false;
    }
    return true;
  }
}
