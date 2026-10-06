import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../routes/app_navigator.dart';
import '../../chat_logic.dart';
import '../../media/chat_media_message_locator.dart';

enum ChatHistoryNavigationFailure { unavailable, expired, failed }

/// A concrete chat route and the positioning facade belonging to that route.
/// Keeping the route identity avoids popping to an unrelated chat by its name.
class ChatHistoryActiveChat {
  const ChatHistoryActiveChat({
    required this.conversationID,
    required this.route,
    required this.isCurrent,
    required this.focusMessage,
  });

  final String conversationID;
  final Route<dynamic>? route;
  final bool Function() isCurrent;
  final Future<bool> Function(Message message) focusMessage;
}

typedef ChatHistoryStartChat = Future<void> Function(
  ConversationInfo conversation,
  Message message,
  bool Function() isEntryCurrent,
);

/// Opens a real chat or returns to its existing route before positioning.
/// History loading and highlighting remain owned by [ChatLogic].
class ChatHistoryMessageNavigation {
  ChatHistoryMessageNavigation({
    Future<Message?> Function(String conversationID, String clientMsgID)?
        findMessage,
    Future<ConversationInfo?> Function(String conversationID)? findConversation,
    ChatHistoryActiveChat? Function(String conversationID)? currentChat,
    ChatHistoryStartChat? startChat,
    Object? Function()? currentSession,
    void Function(ChatHistoryNavigationFailure failure)? showFeedback,
  })  : _findMessage = findMessage ?? _findStoredMessage,
        _findConversation = findConversation ?? _findStoredConversation,
        _currentChat = currentChat ?? _findCurrentChat,
        _startChat = startChat ?? _openNewChat,
        _currentSession = currentSession ?? _readSession,
        _showFeedback = showFeedback ?? _showDefaultFeedback {
    _owner = _currentSession();
  }

  final Future<Message?> Function(String, String) _findMessage;
  final Future<ConversationInfo?> Function(String) _findConversation;
  final ChatHistoryActiveChat? Function(String) _currentChat;
  final ChatHistoryStartChat _startChat;
  final Object? Function() _currentSession;
  final void Function(ChatHistoryNavigationFailure) _showFeedback;
  late final Object? _owner;
  bool _opening = false;

  bool get _sameSession => _owner != null && _owner == _currentSession();

  Future<bool> open(
    BuildContext context, {
    required String conversationID,
    required Message message,
    required bool Function() isEntryCurrent,
  }) async {
    if (_opening || !context.mounted || !_sameSession || !isEntryCurrent()) {
      return false;
    }
    final entryRoute = ModalRoute.of(context);
    final navigator = Navigator.maybeOf(context);
    bool entryCurrent() =>
        context.mounted &&
        _sameSession &&
        isEntryCurrent() &&
        navigator != null &&
        entryRoute?.isActive == true &&
        entryRoute?.isCurrent == true &&
        identical(entryRoute?.navigator, navigator);

    if (_opening || !entryCurrent()) return false;
    final clientMsgID = message.clientMsgID?.trim() ?? '';
    if (conversationID.trim().isEmpty || clientMsgID.isEmpty) {
      _showFeedback(ChatHistoryNavigationFailure.unavailable);
      return false;
    }
    if (message.hasExpired) {
      _showFeedback(ChatHistoryNavigationFailure.expired);
      return false;
    }

    _opening = true;
    var feedbackCurrent = entryCurrent;
    FocusScope.of(context).unfocus();
    try {
      // Search rows are snapshots. Revalidate the exact SDK identity before a
      // historical window can restore a message deleted after the search.
      final target = await _findMessage(conversationID, clientMsgID);
      if (!entryCurrent()) return false;
      if (target == null || target.clientMsgID != clientMsgID) {
        _showFeedback(ChatHistoryNavigationFailure.unavailable);
        return false;
      }
      if (message.hasExpired || target.hasExpired) {
        _showFeedback(ChatHistoryNavigationFailure.expired);
        return false;
      }

      final chat = _currentChat(conversationID);
      final route = chat?.route;
      if (chat != null &&
          chat.conversationID == conversationID &&
          chat.isCurrent() &&
          route?.isActive == true &&
          identical(route?.navigator, navigator)) {
        if (!entryCurrent()) return false;
        // The entry is deliberately disposed by this pop. From this point on,
        // only the captured owner and the concrete destination may cancel it.
        feedbackCurrent = () =>
            _sameSession &&
            chat.isCurrent() &&
            route!.isActive &&
            route.isCurrent;
        navigator!.popUntil((candidate) => identical(candidate, route));
        if (!feedbackCurrent()) return false;
        final focused = await chat.focusMessage(target);
        if (!feedbackCurrent()) return false;
        if (!focused) _showFeedback(ChatHistoryNavigationFailure.failed);
        return focused;
      }

      final conversation = await _findConversation(conversationID);
      if (!entryCurrent()) return false;
      if (conversation == null ||
          conversation.conversationID != conversationID) {
        _showFeedback(ChatHistoryNavigationFailure.unavailable);
        return false;
      }
      if (message.hasExpired || target.hasExpired) {
        _showFeedback(ChatHistoryNavigationFailure.expired);
        return false;
      }
      await _startChat(conversation, target, entryCurrent);
      return _sameSession;
    } catch (_) {
      if (feedbackCurrent()) _showFeedback(ChatHistoryNavigationFailure.failed);
      return false;
    } finally {
      _opening = false;
    }
  }

  static Object? _readSession() {
    final userID = OpenIM.iMManager.userID;
    if (userID.trim().isEmpty) return null;
    return (
      userID,
      OpenIM.iMManager.token,
      DataSp.imToken,
      DataSp.chatToken,
    );
  }

  static Future<Message?> _findStoredMessage(
          String conversationID, String id) =>
      ChatMediaMessageLocator.findStoredMessage(
          conversationID: conversationID, clientMsgID: id);

  static Future<ConversationInfo?> _findStoredConversation(String id) async {
    final conversations = await OpenIM.iMManager.conversationManager
        .getMultipleConversation(conversationIDList: [id]);
    final matches = conversations.where((item) => item.conversationID == id);
    return matches.length == 1 ? matches.single : null;
  }

  static ChatHistoryActiveChat? _findCurrentChat(String conversationID) {
    final tag = GetTags.chat;
    if (tag == null || !Get.isRegistered<ChatLogic>(tag: tag)) return null;
    final logic = Get.find<ChatLogic>(tag: tag);
    if (!logic.isMessageNavigationCurrent ||
        logic.conversationInfo.conversationID != conversationID) {
      return null;
    }
    return ChatHistoryActiveChat(
        conversationID: conversationID,
        route: logic.messageRoute,
        isCurrent: () =>
            logic.isMessageNavigationCurrent &&
            logic.conversationInfo.conversationID == conversationID,
        focusMessage: logic.focusSearchMessage);
  }

  static Future<void> _openNewChat(ConversationInfo conversation,
      Message message, bool Function() isEntryCurrent) async {
    await AppNavigator.startChat<void>(
        conversationInfo: conversation,
        offUntilHome: false,
        searchMessage: message,
        isCurrent: isEntryCurrent);
  }

  static void _showDefaultFeedback(ChatHistoryNavigationFailure failure) =>
      IMViews.showToast(failure == ChatHistoryNavigationFailure.expired
          ? 'sdkExpired'.tr
          : 'chatHistoryLoadFailed'.tr);
}
