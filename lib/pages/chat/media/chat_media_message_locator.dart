import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_picture_gallery.dart';

enum ChatMediaLocationFailure {
  messageUnavailable,
  messageExpired,
  positionFailed,
}

/// Resolves one preview index and delegates positioning to the chat owner.
/// SDK loading, history windows and scrolling remain with the existing owner.
class ChatMediaMessageLocator {
  ChatMediaMessageLocator({
    required this.gallery,
    required this.isCurrent,
    required this.currentMessage,
    required this.findMessage,
    required this.jumpToMessage,
    required this.showFeedback,
    bool Function()? isPositioningCurrent,
  }) : _isPositioningCurrent = isPositioningCurrent ?? isCurrent;

  final ChatPictureGallery gallery;
  final bool Function() isCurrent;
  final Message? Function(String id) currentMessage;
  final Future<Message?> Function(String id) findMessage;
  final Future<bool> Function(Message message) jumpToMessage;
  final void Function(ChatMediaLocationFailure failure) showFeedback;
  final bool Function() _isPositioningCurrent;
  bool _locating = false;
  bool get _canPosition => isCurrent() && _isPositioningCurrent();

  /// Forwarding and deletion require a record still owned by this chat window.
  Message? currentMessageAt(int index) => _resolve(index, requireLoaded: true);

  Message? _resolve(int index, {required bool requireLoaded}) {
    if (!isCurrent()) return null;
    final snapshot = gallery.messageAt(index);
    if (snapshot == null || !_isMedia(snapshot)) {
      showFeedback(ChatMediaLocationFailure.messageUnavailable);
      return null;
    }
    final current = currentMessage(snapshot.clientMsgID!);
    if (snapshot.hasExpired || current?.hasExpired == true) {
      showFeedback(ChatMediaLocationFailure.messageExpired);
      return null;
    }
    if ((requireLoaded && current == null) ||
        (current != null &&
            (current.clientMsgID != snapshot.clientMsgID ||
                !_isMedia(current)))) {
      showFeedback(ChatMediaLocationFailure.messageUnavailable);
      return null;
    }
    return requireLoaded ? Message.fromJson(current!.toJson()) : snapshot;
  }

  Future<bool> viewInChat(int index) async {
    if (_locating || !_canPosition) return false;
    var message = _resolve(index, requireLoaded: false);
    if (message == null) return false;
    _locating = true;
    try {
      // A paged-out snapshot is not evidence that its SDK record still exists.
      // Confirm only that one identity before a history window can insert it.
      if (currentMessage(message.clientMsgID!) == null) {
        final found = await findMessage(message.clientMsgID!);
        if (!_canPosition) return false;
        if (found == null ||
            found.clientMsgID != message.clientMsgID ||
            !_isMedia(found)) {
          showFeedback(ChatMediaLocationFailure.messageUnavailable);
          return false;
        }
        if (message.hasExpired || found.hasExpired) {
          showFeedback(ChatMediaLocationFailure.messageExpired);
          return false;
        }
        final current = currentMessage(message.clientMsgID!);
        if (current != null && (!_isMedia(current) || current.hasExpired)) {
          showFeedback(current.hasExpired
              ? ChatMediaLocationFailure.messageExpired
              : ChatMediaLocationFailure.messageUnavailable);
          return false;
        }
        message = found;
      }
      if (!_canPosition) return false;
      final positioned = await jumpToMessage(message);
      if (!_canPosition) return false;
      if (!positioned) showFeedback(ChatMediaLocationFailure.positionFailed);
      return positioned;
    } catch (_) {
      if (_canPosition) showFeedback(ChatMediaLocationFailure.positionFailed);
      return false;
    } finally {
      _locating = false;
    }
  }

  static bool _isMedia(Message message) =>
      message.contentType == MessageType.picture ||
      message.contentType == MessageType.video;

  /// Exact local SDK lookup, scoped to the already open conversation.
  static Future<Message?> findStoredMessage({
    required String conversationID,
    required String clientMsgID,
  }) async {
    if (conversationID.trim().isEmpty || clientMsgID.trim().isEmpty) {
      return null;
    }
    final result =
        await OpenIM.iMManager.messageManager.findMessageList(searchParams: [
      SearchParams(
          conversationID: conversationID, clientMsgIDList: [clientMsgID])
    ]);
    for (final item
        in result.findResultItems ?? result.searchResultItems ?? []) {
      if (item.conversationID != conversationID) continue;
      for (final message in item.messageList ?? <Message>[]) {
        if (message.clientMsgID == clientMsgID) {
          return Message.fromJson(message.toJson());
        }
      }
    }
    return null;
  }
}
