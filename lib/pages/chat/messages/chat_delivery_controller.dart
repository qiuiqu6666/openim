import 'dart:async';

import 'package:flutter/foundation.dart';
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
    Stream<MsgStreamEv<int>>? uploadProgress,
    Future<FavoriteSendResult> Function(Message, FavoriteTarget)? lookup,
    this.onDeliveryStarted,
    this.onDeliveryFinished,
    this.onTimelineChanged,
  })  : _conversation = conversation,
        _isClosed = isClosed,
        _groupStatus = groupStatus,
        _reset = resetInput,
        _currentAccountID = currentAccountID ?? (() => OpenIM.iMManager.userID),
        _accountID = accountID ?? OpenIM.iMManager.userID,
        _sendRaw = sendRaw ?? ChatMessageSender().sendRaw,
        _lookup = lookup ?? ChatMessageSender().lookup {
    _progressSubscription = uploadProgress?.listen((event) {
      if (this.isClosed || !_transfers.containsKey(event.id)) return;
      final value = event.value.clamp(0, 100);
      updateTransfer(
          event.id, ChatTransferStatus(ChatTransferStage.uploading, value));
    });
  }

  final RxList<Message> messageList;
  final ConversationInfo Function() _conversation;
  final bool Function() _isClosed;
  final int? Function() _groupStatus;
  final void Function() scrollBottom;
  final void Function(Message) _reset;
  final String _accountID;
  final String Function() _currentAccountID;
  final Future<Message> Function(Message, FavoriteTarget) _sendRaw;
  final Future<FavoriteSendResult> Function(Message, FavoriteTarget) _lookup;
  StreamSubscription<MsgStreamEv<int>>? _progressSubscription;
  final _transfers = <String, ValueNotifier<ChatTransferStatus?>>{};
  final _checking = <String>{};
  final _inFlight = <String, Future>{};
  final _deadlines = <String, Timer>{};
  ValueListenable<ChatTransferStatus?>? transferFor(Message message) {
    final id = message.clientMsgID;
    if (isClosed ||
        id == null ||
        message.sendID != _accountID ||
        message.status != MessageStatus.sending) {
      return null;
    }
    return _transfers.putIfAbsent(id, () => ValueNotifier(null));
  }

  void updateTransfer(String? id, ChatTransferStatus value) {
    if (isClosed || id == null) return;
    _deadlines.remove(id)?.cancel();
    if (value.stage == ChatTransferStage.confirming ||
        value.stage == ChatTransferStage.uploading) {
      _deadlines[id] = Timer(const Duration(seconds: 30), () {
        if (isClosed) return;
        final message =
            messageList.firstWhereOrNull((item) => item.clientMsgID == id);
        if (message?.status == MessageStatus.sending) {
          updateTransfer(
              id, const ChatTransferStatus(ChatTransferStage.unknown));
          unawaited(checkDelivery(message!));
        }
      });
    }
    final current = _transfers.putIfAbsent(id, () => ValueNotifier(null));
    if (current.value?.stage != value.stage ||
        current.value?.percent != value.percent) {
      current.value = value;
    }
  }

  Future<void> checkDelivery(Message message) async {
    final id = message.clientMsgID;
    if (isClosed || id == null || !_checking.add(id)) return;
    try {
      final result = await _lookup(
          Message.fromJson(message.toJson()),
          FavoriteTarget(
              conversationID: conversationInfo.conversationID,
              userID: userID,
              groupID: groupID));
      if (isClosed) return;
      if (result.isSuccess && result.message != null) {
        sendSucceeded(message, result.message!);
        _completed();
      } else {
        updateTransfer(id, const ChatTransferStatus(ChatTransferStage.unknown));
      }
    } catch (_) {
      if (!isClosed) {
        updateTransfer(id, const ChatTransferStatus(ChatTransferStage.unknown));
      }
    } finally {
      _checking.remove(id);
    }
  }

  // Presentation hooks share delivery across text, attachments and retry.
  final Object? Function(Message, FavoriteTarget)? onDeliveryStarted;
  final void Function(Object?, Message)? onDeliveryFinished;
  // The route owns automatic-window limits and reading/selection protection.
  final void Function()? onTimelineChanged;
  final sendStatusSub = PublishSubject<MsgStreamEv<bool>>();
  bool _closed = false;
  bool get isClosed =>
      _closed || _isClosed() || _accountID != _currentAccountID();
  ConversationInfo get conversationInfo => _conversation();
  String? get userID => conversationInfo.userID;
  String? get groupID => conversationInfo.groupID;
  bool get isSingleChat => userID?.trim().isNotEmpty == true;

  void _completed() {
    onTimelineChanged?.call();
    messageList.refresh();
  }

  void close() {
    _closed = true;
    for (final timer in _deadlines.values) {
      timer.cancel();
    }
    _deadlines.clear();
    _progressSubscription?.cancel();
    for (final notifier in _transfers.values) {
      notifier.dispose();
    }
    _transfers.clear();
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
    int? destinationSessionType,
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
    Logger.print('send type:${message.contentType} id:${message.clientMsgID}',
        onlyConsole: true);
    final messageID = message.clientMsgID;
    if (messageID != null && _inFlight.containsKey(messageID)) {
      return _inFlight[messageID]!;
    }
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
          onTimelineChanged?.call();
        }
        scrollBottom();
      }
    }
    Logger.print('uid:$userID userId:$userId gid:$groupID groupId:$groupId');
    if (resetInput) _reset(message);
    bool useOuterValue = null != userId || null != groupId;

    final recvUserID = useOuterValue ? userId : userID;
    message.recvID = recvUserID;
    final target = FavoriteTarget(
      conversationID: conversationInfo.conversationID,
      userID: recvUserID,
      groupID: useOuterValue ? groupId : groupID,
      sessionType: destinationSessionType ??
          (!useOuterValue ||
                  (groupId != null && groupId == groupID) ||
                  (userId != null && userId == userID)
              ? conversationInfo.conversationType
              : null),
    );
    final presentation = onDeliveryStarted?.call(message, target);
    updateTransfer(message.clientMsgID,
        const ChatTransferStatus(ChatTransferStage.confirming));
    final operation = _sendRaw(message, target).then((value) {
      if (value.clientMsgID != message.clientMsgID) {
        updateTransfer(message.clientMsgID,
            const ChatTransferStatus(ChatTransferStage.unknown));
        favoriteResult?.call(FavoriteSendResult(
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
    }).catchError((Object error, StackTrace stack) async {
      final result = ChatMessageSender.resultForError(error, message);
      if (!isClosed && account == _currentAccountID()) {
        if (result.status == FavoriteSendStatus.failed) {
          _senFailed(message, groupId, userId, error, stack);
        } else if (favoriteResult == null) {
          updateTransfer(message.clientMsgID,
              const ChatTransferStatus(ChatTransferStage.unknown));
          await checkDelivery(message);
        }
      }
      favoriteResult?.call(result);
    }).whenComplete(() {
      _deadlines.remove(messageID)?.cancel();
      _inFlight.remove(messageID);
      onDeliveryFinished?.call(presentation, message);
      if (!isClosed && account == _currentAccountID()) _completed();
    });
    if (messageID != null) _inFlight[messageID] = operation;
    return operation;
  }

  void sendSucceeded(Message oldMsg, Message newMsg) {
    _deadlines.remove(oldMsg.clientMsgID)?.cancel();
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
