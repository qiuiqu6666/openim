import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../../../routes/app_navigator.dart';
import '../../../../services/favorite_send_coordinator.dart';
import '../../../contacts/select_contacts/select_contacts_logic.dart';
import '../chat_delivery_controller.dart';

typedef ForwardContactPicker = Future<dynamic> Function(String description);
typedef ContactCardPicker = Future<dynamic> Function({
  required SelAction action,
  UserInfo? sharedContact,
  String? cardRecipientName,
  String? cardRecipientFaceURL,
  bool? cardRecipientIsGroup,
  String? ex,
});
typedef ForwardMessageBuilder = Future<Message> Function(Message original);
typedef MergedMessageBuilder = Future<Message> Function({
  required List<Message> messageList,
  required String title,
  required List<String> summaryList,
});

/// Contact cards and single/merged message forwarding.
class ChatForwardingController {
  ChatForwardingController({
    required ChatDeliveryController delivery,
    required List<Message> Function() messages,
    required bool Function() isClosed,
    required bool Function() isGroupChat,
    required String Function() nickname,
    required String Function() faceUrl,
    required this.canForward,
    required this.closeToolbox,
    ForwardContactPicker? selectContacts,
    ContactCardPicker? selectCardContacts,
    Future<String> Function(String userID)? createCardExtension,
    ForwardMessageBuilder? createForward,
    MergedMessageBuilder? createMerger,
    void Function(String)? showToast,
    this.onForwardNeedsReview,
  })  : _delivery = delivery,
        _messages = messages,
        _isClosed = isClosed,
        _isGroupChat = isGroupChat,
        _nickname = nickname,
        _faceUrl = faceUrl,
        _selectContacts = selectContacts ??
            ((description) async => AppNavigator.startSelectContacts(
                action: SelAction.forward, ex: description)),
        _selectCardContacts = selectCardContacts ??
            ((
                    {required action,
                    sharedContact,
                    cardRecipientName,
                    cardRecipientFaceURL,
                    cardRecipientIsGroup,
                    ex}) async =>
                AppNavigator.startSelectContacts(
                    action: action,
                    sharedContact: sharedContact,
                    cardRecipientName: cardRecipientName,
                    cardRecipientFaceURL: cardRecipientFaceURL,
                    cardRecipientIsGroup: cardRecipientIsGroup ?? false,
                    ex: ex)),
        _createCardExtension = createCardExtension,
        _createForward = createForward ??
            ((original) => OpenIM.iMManager.messageManager
                .createForwardMessage(message: original)),
        _createMerger = createMerger ??
            (({required messageList, required title, required summaryList}) =>
                OpenIM.iMManager.messageManager.createMergerMessage(
                    messageList: messageList,
                    title: title,
                    summaryList: summaryList)),
        _showToast = showToast ?? ((text) => IMViews.showToast(text));

  final ChatDeliveryController _delivery;
  final List<Message> Function() _messages;
  final bool Function() _isClosed, _isGroupChat;
  final String Function() _nickname, _faceUrl;
  final ForwardContactPicker _selectContacts;
  final ContactCardPicker _selectCardContacts;
  final Future<String> Function(String userID)? _createCardExtension;
  final ForwardMessageBuilder _createForward;
  final MergedMessageBuilder _createMerger;
  final void Function(String) _showToast;
  final bool Function(Message) canForward;
  final void Function() closeToolbox;
  final void Function()? onForwardNeedsReview;
  bool get isClosed => _isClosed() || _delivery.isClosed;
  bool get isGroupChat => _isGroupChat();
  List<Message> get messageList => _messages();
  bool _isFundMessage(Message message) =>
      message.contentType == MessageType.custom &&
      FundMessageData.tryParse(message.customElem?.data) != null;
  Future _sendMessage(Message message, {String? userId, String? groupId}) =>
      _delivery.send(message, userId: userId, groupId: groupId);

  Future<void> forwardMessage(Message message) async {
    await _forwardMessages([message],
        merged: false, requireCurrentSources: false);
  }

  Future<void> sendForwardRemarkMsg(
    String content, {
    String? userId,
    String? groupId,
  }) async {
    final message = await OpenIM.iMManager.messageManager.createTextMessage(
      text: content,
    );
    _sendMessage(message, userId: userId, groupId: groupId);
  }

  Future<void> sendForwardMsg(
    Message originalMessage, {
    String? userId,
    String? groupId,
  }) async {
    // Funds cards reference their original order and conversation; only the
    // funds backend may create or deliver these records.
    if (_isFundMessage(originalMessage)) return;
    var message = await OpenIM.iMManager.messageManager.createForwardMessage(
      message: originalMessage,
    );
    _sendMessage(message, userId: userId, groupId: groupId);
  }

  Future<void> mergeForward(Message initial) async {
    await _forwardMessages([initial],
        merged: true, requireCurrentSources: false);
  }

  List<Message>? _resolveSelection(List<Message> selection, List<String?> ids,
      {required bool merged,
      required bool requireCurrentSources,
      required void Function(String) onInvalid}) {
    if (isClosed || selection.isEmpty) return null;
    if (selection.length > (merged ? 100 : 30)) {
      onInvalid(
          (merged ? 'chatSelectionMergeLimit' : 'chatSelectionForwardLimit')
              .tr);
      return null;
    }
    final current = requireCurrentSources
        ? {for (final message in messageList) message.clientMsgID: message}
        : null;
    final seen = <String>{};
    final resolved = <({Message message, int index})>[];
    for (var index = 0; index < selection.length; index++) {
      final id = ids[index];
      final message = requireCurrentSources ? current![id] : selection[index];
      if (id == null ||
          id.trim().isEmpty ||
          !seen.add(id) ||
          message == null ||
          message.clientMsgID != id ||
          _isFundMessage(message) ||
          message.hasExpired ||
          !canForward(message)) {
        onInvalid('chatSelectionForwardBlocked'.tr);
        return null;
      }
      resolved.add((message: message, index: index));
    }
    resolved.sort((first, next) {
      final time =
          (first.message.sendTime ?? 0).compareTo(next.message.sendTime ?? 0);
      return time != 0 ? time : first.index.compareTo(next.index);
    });
    return resolved.map((item) => item.message).toList(growable: false);
  }

  /// One contact selection, then a stable chronological batch. Never forward a
  /// silently filtered subset when a selected message is no longer eligible.
  Future<bool> forwardMessages(List<Message> selection,
          {required bool merged}) =>
      _forwardMessages(selection, merged: merged, requireCurrentSources: true);

  Future<bool> _forwardMessages(List<Message> selection,
      {required bool merged, required bool requireCurrentSources}) async {
    final snapshot = List<Message>.of(selection);
    final selectedIDs = snapshot.map((message) => message.clientMsgID).toList();
    String? invalidHint;
    var confirmedCount = 0;
    var uncertain = false;
    var reviewNotified = false;
    List<Message>? resolve() {
      invalidHint = null;
      return _resolveSelection(snapshot, selectedIDs,
          merged: merged,
          requireCurrentSources: requireCurrentSources,
          onInvalid: (hint) => invalidHint = hint);
    }

    bool fail({String? hint}) {
      if (isClosed) return false;
      if (requireCurrentSources && (confirmedCount > 0 || uncertain)) {
        // Keeping the selection would let a retry resend accepted messages.
        // An uncertain receipt also requires checking the destination first.
        if (!reviewNotified) {
          reviewNotified = true;
          _showToast((uncertain
                  ? 'chatSelectionForwardUncertain'
                  : 'chatSelectionForwardPartial')
              .tr);
          onForwardNeedsReview?.call();
        }
      } else if (hint?.trim().isNotEmpty == true) {
        _showToast(hint!);
      }
      return false;
    }

    Future<bool> send(
        Message message, ({String? userID, String? groupID}) target) async {
      final receipt = await _sendForwarded(message, target);
      if (isClosed) return false;
      if (receipt?.isSuccess == true) {
        confirmedCount++;
        return true;
      }
      uncertain =
          receipt == null || receipt.status == FavoriteSendStatus.unknown;
      return fail(hint: receipt?.errorMessage ?? StrRes.sendFailed);
    }

    try {
      var messages = resolve();
      if (messages == null) return fail(hint: invalidHint);
      final result = await _selectContacts(merged
          ? 'sdkMergedHistory'.tr
          : IMUtils.parseMsg(messages.first, isConversation: true));
      messages = resolve();
      if (messages == null) return fail(hint: invalidHint);
      if (result == null || result is! Map) return false;
      final checked = result['checkedList'];
      if (checked is! Iterable || checked.isEmpty) return false;
      final targets = <({String? userID, String? groupID})>[];
      for (final contact in checked) {
        final userID =
            IMUtils.emptyStrToNull(IMUtils.convertCheckedToUserID(contact));
        final groupID =
            IMUtils.emptyStrToNull(IMUtils.convertCheckedToGroupID(contact));
        if ((userID != null) == (groupID != null)) return false;
        targets.add((userID: userID, groupID: groupID));
      }
      final orderedIDs =
          messages.map((message) => message.clientMsgID!).toList();
      for (final target in targets) {
        messages = resolve();
        if (messages == null) return fail(hint: invalidHint);
        if (merged) {
          final message = await _createMerger(
              messageList: messages,
              title: '${_nickname()} · ${'sdkMergedHistory'.tr}',
              summaryList: messages
                  .take(3)
                  .map((m) =>
                      '${m.senderNickname ?? ''}: ${IMUtils.parseMsg(m)}')
                  .toList());
          if (resolve() == null) return fail(hint: invalidHint);
          if (!await send(message, target)) return false;
          if (resolve() == null) return fail(hint: invalidHint);
        } else {
          for (final id in orderedIDs) {
            messages = resolve();
            if (messages == null) return fail(hint: invalidHint);
            final original =
                messages.firstWhere((item) => item.clientMsgID == id);
            final message = await _createForward(original);
            if (resolve() == null) return fail(hint: invalidHint);
            if (!await send(message, target)) return false;
            if (resolve() == null) return fail(hint: invalidHint);
          }
        }
      }
      return true;
    } catch (error) {
      return fail(hint: error.toString());
    }
  }

  Future<FavoriteSendResult?> _sendForwarded(
      Message message, ({String? userID, String? groupID}) target) async {
    if (isClosed) return null;
    FavoriteSendResult? result;
    await _delivery.send(message,
        userId: target.userID,
        groupId: target.groupID,
        resetInput: false,
        favoriteResult: (value) => result = value);
    return result;
  }

  Future<void> onTapCard() async {
    final current = _cardSessionGuard();
    if (!current()) return;
    try {
      closeToolbox();
      if (!current()) return;
      final selected = await _selectCardContacts(
        action: SelAction.carte,
        cardRecipientName: _nickname(),
        cardRecipientFaceURL: _faceUrl(),
        cardRecipientIsGroup: isGroupChat,
      );
      if (!current() ||
          selected is! UserInfo ||
          selected.userID?.isNotEmpty != true) {
        return;
      }
      await _sendCarte(
        userID: selected.userID!,
        nickname: selected.nickname,
        faceURL: selected.faceURL,
        current: current,
      );
    } catch (error) {
      if (!current()) return;
      Logger.print('Send contact card failed: $error');
      _showToast(StrRes.sendFailed);
    }
  }

  Future<void> sendCarte({
    required String userID,
    String? nickname,
    String? faceURL,
  }) =>
      _sendCarte(
          userID: userID,
          nickname: nickname,
          faceURL: faceURL,
          current: _cardSessionGuard());

  Future<void> _sendCarte({
    required String userID,
    required bool Function() current,
    String? nickname,
    String? faceURL,
    String? recipientUserID,
    String? recipientGroupID,
  }) async {
    if (!current()) return;
    final extension = await _cardExtension(userID, current);
    if (!current() || extension == null) return;
    final message = await OpenIM.iMManager.messageManager.createCardMessage(
      userID: userID,
      ex: extension,
      nickname: nickname?.trim().isNotEmpty == true ? nickname! : userID,
      faceURL: faceURL,
    );
    if (!current()) return;
    await _sendMessage(message,
        userId: recipientUserID, groupId: recipientGroupID);
    if (!current()) return;
  }

  bool Function() _cardSessionGuard() {
    final owner = DataSp.userID;
    final token = DataSp.chatToken;
    final sdkOwner = OpenIM.iMManager.userID;
    return () =>
        !isClosed &&
        DataSp.userID == owner &&
        DataSp.chatToken == token &&
        OpenIM.iMManager.userID == sdkOwner;
  }

  Future<String?> _cardExtension(String userID, bool Function() current) async {
    if (!current()) return null;
    if (_createCardExtension != null) {
      final extension = await _createCardExtension(userID);
      return current() ? extension : null;
    }
    final account = await ContactCardProfileResolver.shared.resolve(userID);
    if (!current()) return null;
    final extension = await createFriendCardExtension(userID, account: account);
    return current() ? extension : null;
  }

  Future<void> recommendFriendCarte(UserInfo userInfo) async {
    final current = _cardSessionGuard();
    final cardUserID = userInfo.userID;
    final nickname = userInfo.nickname;
    final faceURL = userInfo.faceURL;
    if (!current() || cardUserID?.isNotEmpty != true) return;
    try {
      final result = await _selectCardContacts(
        action: SelAction.recommend,
        sharedContact: userInfo,
        ex: '[${StrRes.carte}]$nickname',
      );
      if (!current() || result is! Map) return;
      final customEx = result['customEx'];
      final checkedList = result['checkedList'];
      if (checkedList is! Iterable) return;
      for (final info in checkedList) {
        if (!current()) return;
        final userID = IMUtils.convertCheckedToUserID(info);
        final groupID = IMUtils.convertCheckedToGroupID(info);
        if (customEx is String && customEx.isNotEmpty) {
          final remark =
              await OpenIM.iMManager.messageManager.createTextMessage(
            text: customEx,
          );
          if (!current()) return;
          await _sendMessage(
            remark,
            userId: userID,
            groupId: groupID,
          );
          if (!current()) return;
        }
        await _sendCarte(
          userID: cardUserID!,
          nickname: nickname,
          faceURL: faceURL,
          current: current,
          recipientUserID: userID,
          recipientGroupID: groupID,
        );
        if (!current()) return;
      }
    } catch (error) {
      if (!current()) return;
      Logger.print('Recommend contact card failed: $error');
      _showToast(StrRes.sendFailed);
    }
  }
}
