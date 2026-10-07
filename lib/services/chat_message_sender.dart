import '../core/user_activity/activity_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'favorite_send_coordinator.dart';

typedef FavoriteSdkTransport = Future<Message> Function(
    Message message, FavoriteTarget target);
typedef FavoriteSdkLookup = Future<SearchResult> Function(SearchParams params);

class MessageSendValidationException extends FormatException {
  const MessageSendValidationException(super.message);
}

/// A shared SDK transport without a dependency on a mounted chat page.
class ChatMessageSender {
  ChatMessageSender({
    FavoriteSdkTransport? transport,
    FavoriteSdkLookup? lookup,
    String Function()? accountProvider,
  })  : _transport = transport,
        _lookup = lookup,
        _accountProvider = accountProvider;

  final FavoriteSdkTransport? _transport;
  final FavoriteSdkLookup? _lookup;
  final String Function()? _accountProvider;

  Future<Message> sendRaw(Message message, FavoriteTarget target) async {
    final user = target.userID?.trim();
    final group = target.groupID?.trim();
    final hasUser = user?.isNotEmpty == true;
    final hasGroup = group?.isNotEmpty == true;
    if (hasUser == hasGroup) {
      throw const MessageSendValidationException(
          'Exactly one message destination is required');
    }
    if (message.clientMsgID?.isNotEmpty != true) {
      throw const MessageSendValidationException(
          'Create a new message before sending');
    }
    if (_transport != null) return _transport(message, target);
    return observeUserActivity(
        messageActivity(message.contentType),
        () => OpenIM.iMManager.messageManager.sendMessage(
              message: message,
              userID: hasUser ? user : null,
              groupID: hasGroup ? group : null,
              offlinePushInfo: Config.offlinePushInfo,
            ));
  }

  Future<FavoriteSendResult> send(
      Message message, FavoriteTarget target) async {
    final owner = _accountProvider?.call() ?? OpenIM.iMManager.userID;
    if (owner.isEmpty) {
      return FavoriteSendResult(
        status: FavoriteSendStatus.failed,
        clientMsgID: message.clientMsgID,
        errorCode: 'LOGIN_REQUIRED',
        errorMessage: '请先登录后发送',
      );
    }
    try {
      final sent = await sendRaw(message, target);
      final current = _accountProvider?.call() ?? OpenIM.iMManager.userID;
      if (owner != current || sent.clientMsgID != message.clientMsgID) {
        return FavoriteSendResult(
          status: FavoriteSendStatus.unknown,
          clientMsgID: message.clientMsgID,
          message: message,
          errorCode: 'RECEIPT_UNCONFIRMED',
          errorMessage: '发送状态待确认，请先核对会话',
        );
      }
      message.update(sent);
      return FavoriteSendResult(
        status: FavoriteSendStatus.success,
        clientMsgID: sent.clientMsgID,
        message: sent,
        sentCount: 1,
      );
    } catch (error) {
      return resultForError(error, message);
    }
  }

  /// Query an existing ID; absence or a local failed record never permits a
  /// fresh send. Only an accepted message in the fixed destination confirms it.
  Future<FavoriteSendResult> lookup(
      Message message, FavoriteTarget target) async {
    final owner = _accountProvider?.call() ?? OpenIM.iMManager.userID;
    final id = message.clientMsgID;
    FavoriteSendResult unconfirmed() => FavoriteSendResult.unknown(
        clientMsgID: id,
        message: message,
        errorCode: 'SEND_UNCONFIRMED',
        errorMessage: '发送状态待确认，请先核对会话，避免重复发送');
    if (owner.isEmpty || id == null || id.isEmpty || !target.isValid) {
      return unconfirmed();
    }
    try {
      final params = SearchParams(
          conversationID: target.conversationID, clientMsgIDList: [id]);
      final result = _lookup != null
          ? await _lookup(params)
          : await OpenIM.iMManager.messageManager
              .findMessageList(searchParams: [params]);
      if (owner != (_accountProvider?.call() ?? OpenIM.iMManager.userID)) {
        return unconfirmed();
      }
      final groups = result.findResultItems ?? result.searchResultItems ?? [];
      for (final group in groups) {
        if (group.conversationID != target.conversationID) continue;
        for (final receipt in group.messageList ?? <Message>[]) {
          final destinationMatches = target.groupID != null
              ? receipt.groupID == target.groupID
              : receipt.recvID == target.userID;
          if (receipt.clientMsgID == id &&
              receipt.sendID == owner &&
              destinationMatches &&
              receipt.status == MessageStatus.succeeded &&
              (receipt.seq ?? 0) > 0) {
            message.update(receipt);
            return FavoriteSendResult.success(message: receipt);
          }
        }
      }
    } catch (_) {
      // Network/SDK query failures keep the original attempt unresolved.
    }
    return unconfirmed();
  }

  /// A failed local record or a timeout is not proof of server rejection.
  static FavoriteSendResult resultForError(Object error, Message message) {
    final code = error is PlatformException ? error.code : null;
    final numeric = int.tryParse(code ?? '');
    final rejected = error is MessageSendValidationException ||
        _confirmedRejections.contains(numeric);
    return FavoriteSendResult(
      status: rejected ? FavoriteSendStatus.failed : FavoriteSendStatus.unknown,
      clientMsgID: message.clientMsgID,
      message: message,
      errorCode: code ?? (rejected ? 'INVALID_MESSAGE' : 'SEND_UNCONFIRMED'),
      // Do not expose SDK exception messages, paths, tokens or asset URLs.
      errorMessage: rejected ? '发送失败，请检查会话权限或消息内容' : '发送状态待确认，请先核对会话，避免重复发送',
      retryable: numeric == SDKErrorCode.fileUploadExpired,
    );
  }

  static const _confirmedRejections = <int>{
    SDKErrorCode.parameterError,
    SDKErrorCode.resourceNotLoaded,
    SDKErrorCode.userHasLoggedOut,
    SDKErrorCode.uploadFileNotExist,
    SDKErrorCode.messageContentTypeNotSupported,
    SDKErrorCode.serverParameterError,
    SDKErrorCode.insufficientPermissions,
    SDKErrorCode.userIDNotExist,
    SDKErrorCode.groupNotExis,
    SDKErrorCode.userIsNotInGroup,
    SDKErrorCode.groupDisbanded,
    SDKErrorCode.hasBeenBlocked,
    SDKErrorCode.notFriend,
    SDKErrorCode.youHaveBeenBanned,
    SDKErrorCode.groupHasBeenBanned,
    SDKErrorCode.tokenHasExpired,
    SDKErrorCode.tokenInvalid,
    SDKErrorCode.tokenFormatError,
    SDKErrorCode.tokenHasNotYetTakenEffect,
    SDKErrorCode.thekickedOutTokenIsInvalid,
    SDKErrorCode.tokenNotExist,
    SDKErrorCode.fileUploadExpired,
  };
}
