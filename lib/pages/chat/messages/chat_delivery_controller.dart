import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';

import '../../../services/chat_message_sender.dart';
import '../../../services/favorite_send_coordinator.dart';

/// Owns message delivery status and SDK failure hints for the chat timeline.
class ChatDeliveryController {
  ChatDeliveryController({
    required this.messageList,
    required ConversationInfo Function() conversation,
    required bool Function() isClosed,
    required int? Function() groupStatus,
    required this.scrollBottom,
    required void Function(Message) resetInput,
    String? accountID,
    String Function()? currentAccountID,
    Future<Message> Function(Message, FavoriteTarget)? sendRaw,
  })  : _conversation = conversation,
        _isClosed = isClosed,
        _groupStatus = groupStatus,
        _reset = resetInput,
        _currentAccountID = currentAccountID ?? (() => OpenIM.iMManager.userID),
        _accountID = accountID ?? OpenIM.iMManager.userID,
        _sendRaw = sendRaw ?? ChatMessageSender().sendRaw;

  final RxList<Message> messageList;
  final ConversationInfo Function() _conversation;
  final bool Function() _isClosed;
  final int? Function() _groupStatus;
  final void Function() scrollBottom;
  final void Function(Message) _reset;
  final String _accountID;
  final String Function() _currentAccountID;
  final Future<Message> Function(Message, FavoriteTarget) _sendRaw;
  final sendStatusSub = PublishSubject<MsgStreamEv<bool>>();
  bool _closed = false;
  bool get isClosed =>
      _closed || _isClosed() || _accountID != _currentAccountID();
  ConversationInfo get conversationInfo => _conversation();
  String? get userID => conversationInfo.userID;
  String? get groupID => conversationInfo.groupID;
  bool get isSingleChat => userID?.trim().isNotEmpty == true;

  void _completed() => messageList.refresh();

  void close() {
    _closed = true;
    sendStatusSub.close();
  }

  Future<void> sendCustomMessage({
    required String data,
    required String extension,
    required String description,
  }) async {
    if (isClosed) return;
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
      data: data,
      extension: extension,
      description: description,
    );
    if (!isClosed) await send(message);
  }

  Future send(
    Message message, {
    String? userId,
    String? groupId,
    bool addToUI = true,
    bool resetInput = true,
    void Function(FavoriteSendResult)? favoriteResult,
  }) {
    if (isClosed) {
      favoriteResult?.call(FavoriteSendResult(
        status: FavoriteSendStatus.failed,
        clientMsgID: message.clientMsgID,
        errorCode: 'CHAT_CLOSED',
        errorMessage: 'favoriteChatChanged'.tr,
      ));
      return Future<void>.value();
    }
    log('send type:${message.contentType} id:${message.clientMsgID}');
    final account = _currentAccountID();
    if (favoriteResult != null) {
      final visible = messageList
          .firstWhereOrNull((item) => item.clientMsgID == message.clientMsgID);
      if (visible != null && !identical(visible, message)) {
        visible.update(message);
        message = visible;
      }
      if (visible != null) messageList.refresh();
      sendStatusSub.addSafely(MsgStreamEv<bool>(
        id: message.clientMsgID!,
        value: true,
      ));
    }
    userId = IMUtils.emptyStrToNull(userId);
    groupId = IMUtils.emptyStrToNull(groupId);
    if (null == userId && null == groupId ||
        userId == userID && userId != null ||
        groupId == groupID && groupId != null) {
      if (addToUI) {
        if (favoriteResult == null ||
            !messageList
                .any((item) => item.clientMsgID == message.clientMsgID)) {
          messageList.add(message);
        }
        scrollBottom();
      }
    }
    Logger.print('uid:$userID userId:$userId gid:$groupID groupId:$groupId');
    if (resetInput) _reset(message);
    bool useOuterValue = null != userId || null != groupId;

    final recvUserID = useOuterValue ? userId : userID;
    message.recvID = recvUserID;

    return _sendRaw(
        message,
        FavoriteTarget(
          conversationID: conversationInfo.conversationID,
          userID: recvUserID,
          groupID: useOuterValue ? groupId : groupID,
        )).then((value) {
      if (favoriteResult != null && value.clientMsgID != message.clientMsgID) {
        favoriteResult(FavoriteSendResult(
          status: FavoriteSendStatus.unknown,
          clientMsgID: message.clientMsgID,
          errorCode: 'RECEIPT_UNCONFIRMED',
          errorMessage: 'favoriteSendUnknown'.tr,
        ));
        return;
      }
      if (!isClosed && account == _currentAccountID()) {
        sendSucceeded(message, value);
      }
      favoriteResult?.call(FavoriteSendResult(
        status: FavoriteSendStatus.success,
        clientMsgID: value.clientMsgID,
        message: value,
        sentCount: 1,
      ));
    }).catchError((Object error, StackTrace stack) {
      final result = ChatMessageSender.resultForError(error, message);
      if (!isClosed && account == _currentAccountID()) {
        if (favoriteResult == null ||
            result.status == FavoriteSendStatus.failed) {
          _senFailed(message, groupId, userId, error, stack);
        }
      }
      favoriteResult?.call(result);
    }).whenComplete(() {
      if (!isClosed && account == _currentAccountID()) _completed();
    });
  }

  void sendSucceeded(Message oldMsg, Message newMsg) {
    Logger.print('message send success----');
    oldMsg.update(newMsg);
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: oldMsg.clientMsgID!,
      value: true,
    ));
  }

  void _senFailed(
      Message message, String? groupId, String? userId, error, stack) async {
    Logger.print('message send failed id:${message.clientMsgID} '
        'code:${error is PlatformException ? error.code : error.runtimeType}');
    message.status = MessageStatus.failed;
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: message.clientMsgID!,
      value: false,
    ));
    if (error is PlatformException) {
      int code = int.tryParse(error.code) ?? 0;
      if (isSingleChat) {
        int? customType;
        if (code == SDKErrorCode.hasBeenBlocked) {
          customType = CustomMessageType.blockedByFriend;
        } else if (code == SDKErrorCode.notFriend) {
          customType = CustomMessageType.deletedByFriend;
        }
        if (null != customType) {
          final hintMessage = (await OpenIM.iMManager.messageManager
              .createFailedHintMessage(type: customType))
            ..status = 2
            ..isRead = true;
          if (isClosed) return;
          if (userId != null) {
            if (userId == userID) {
              messageList.add(hintMessage);
            }
          } else {
            messageList.add(hintMessage);
          }
          OpenIM.iMManager.messageManager.insertSingleMessageToLocalStorage(
            message: hintMessage,
            receiverID: userId ?? userID,
            senderID: OpenIM.iMManager.userID,
          );
        }
      } else {
        if ((code == SDKErrorCode.userIsNotInGroup ||
                code == SDKErrorCode.groupDisbanded) &&
            null == groupId) {
          final status = _groupStatus();
          final hintMessage = (await OpenIM.iMManager.messageManager
              .createFailedHintMessage(
                  type: status == 2
                      ? CustomMessageType.groupDisbanded
                      : CustomMessageType.removedFromGroup))
            ..status = 2
            ..isRead = true;
          if (isClosed) return;
          messageList.add(hintMessage);
          OpenIM.iMManager.messageManager.insertGroupMessageToLocalStorage(
            message: hintMessage,
            groupID: groupID,
            senderID: OpenIM.iMManager.userID,
          );
        }
      }
    }
  }
}
