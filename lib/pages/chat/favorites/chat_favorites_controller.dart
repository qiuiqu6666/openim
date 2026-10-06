import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../../services/chat_message_sender.dart';
import '../../../services/favorite_message_adapter.dart';
import '../../../services/favorite_repository.dart';
import '../../../services/favorite_runtime.dart';
import '../../../services/favorite_send_coordinator.dart';
import '../messages/chat_delivery_controller.dart';
import 'favorite_picker_sheet.dart';

/// Adapts favorite storage and recoverable delivery to the current chat.
class ChatFavoritesController {
  ChatFavoritesController({
    required this.messageList,
    required ChatDeliveryController delivery,
    required ConversationInfo Function() conversation,
    required String accountID,
    required bool Function() isClosed,
    required bool Function() sendingMuted,
    required bool Function() isInvalidGroup,
    required String Function() displayName,
    required void Function() unfocus,
    FavoriteRepository? repository,
  })  : _delivery = delivery,
        _conversation = conversation,
        _chatAccountID = accountID,
        _isClosed = isClosed,
        _sendingMuted = sendingMuted,
        _isInvalidGroup = isInvalidGroup,
        _displayName = displayName,
        _unfocus = unfocus,
        _repository = repository ?? FavoriteRuntime.repository {
    // A route closed before this microtask never starts a capability request.
    scheduleMicrotask(() {
      if (_disposed || _isClosed()) return;
      _repository.addListener(_onCapabilitiesChanged);
      unawaited(_probeCapabilities());
    });
  }

  final RxList<Message> messageList;
  final ChatDeliveryController _delivery;
  final ConversationInfo Function() _conversation;
  final String _chatAccountID;
  final bool Function() _isClosed, _sendingMuted, _isInvalidGroup;
  final String Function() _displayName;
  final void Function() _unfocus;
  final FavoriteRepository _repository;
  final RxBool _capabilitiesReady = false.obs;
  bool _disposed = false;

  void _onCapabilitiesChanged() {
    if (!_disposed && !isClosed) {
      _capabilitiesReady.value = _repository.available;
    }
  }

  Future<void> _probeCapabilities() async {
    try {
      await _repository.ensureCapabilities();
    } catch (_) {/* The picker shows the repository's real retryable error. */}
    _onCapabilitiesChanged();
  }

  void dispose() {
    _disposed = true;
    _repository.removeListener(_onCapabilitiesChanged);
    _capabilitiesReady.close();
  }

  ConversationInfo get conversationInfo => _conversation();
  String? get userID => conversationInfo.userID;
  String? get groupID => conversationInfo.groupID;
  bool get isClosed => _isClosed();
  bool get sendingMuted => _sendingMuted();
  bool get isInvalidGroup => _isInvalidGroup();
  bool _isFundMessage(Message message) =>
      message.contentType == MessageType.custom &&
      FundMessageData.tryParse(message.customElem?.data) != null;
  Future _sendMessage(Message message,
          {bool addToUI = true,
          bool resetInput = true,
          void Function(FavoriteSendResult)? favoriteResult}) =>
      _delivery.send(message,
          addToUI: addToUI,
          resetInput: resetInput,
          favoriteResult: favoriteResult);

  bool _supportsMessage(Message message) =>
      !_isFundMessage(message) &&
      const {
        MessageType.text,
        MessageType.atText,
        MessageType.quote,
        MessageType.advancedText,
        MessageType.picture,
        MessageType.voice,
        MessageType.video,
        MessageType.file,
      }.contains(message.contentType) &&
      FavoriteMessageAdapter.canFavorite(message);

  bool canFavorite(Message message) => !isClosed && _supportsMessage(message);

  Future<void> favoriteMessage(Message message) async {
    if (isClosed || !_supportsMessage(message)) return;
    final account = OpenIM.iMManager.userID;
    final scope = _repository.sessionScope;
    final conversationID = conversationInfo.conversationID;
    try {
      await _repository.requireAvailable();
      if (isClosed ||
          !_repository.isSessionCurrent(scope) ||
          conversationID != conversationInfo.conversationID) {
        return;
      }
      final item = await _repository.createFromMessage(
        source: FavoriteMessageAdapter.sourceForMessage(
          message,
          conversationID: conversationID,
        ),
      );
      if (isClosed || account != OpenIM.iMManager.userID) return;
      IMViews.showToast(switch (item.status) {
        FavoriteStatus.ready => 'favoriteSaved'.tr,
        FavoriteStatus.pendingArchive => 'favoriteSaving'.tr,
        _ => 'favoriteSaveFailed'.tr,
      });
    } catch (error) {
      if (!isClosed && account == OpenIM.iMManager.userID) {
        IMViews.showToast(error is FavoriteApiException
            ? error.message
            : 'favoriteSaveFailed'.tr);
      }
    }
  }

  Future<void> onTapFavorites() async {
    final context = Get.context;
    if (context == null || isClosed) return;
    if (sendingMuted || isInvalidGroup) {
      IMViews.showToast(StrRes.youMuted);
      return;
    }
    final target = FavoriteTarget(
      conversationID: conversationInfo.conversationID,
      userID: IMUtils.emptyStrToNull(userID),
      groupID: IMUtils.emptyStrToNull(groupID),
      displayName: _displayName(),
    );
    final scope = _repository.sessionScope;
    try {
      await _repository.requireAvailable();
    } catch (_) {
      /* Open the capability panel so a failed probe can be retried. */
    }
    if (isClosed ||
        !context.mounted ||
        !_repository.isSessionCurrent(scope) ||
        target.conversationID != conversationInfo.conversationID) {
      return;
    }
    _unfocus();
    await FavoritePickerSheet.show(
      context,
      repository: _repository,
      target: target,
      onSend: (item) => FavoriteRuntime.coordinator.send(
        item,
        target,
        onSend: _sendFavoriteMessage,
        lookup: _lookupFavoriteMessage,
      ),
      onReconcile: (attemptID) => FavoriteRuntime.coordinator.reconcile(
        attemptID,
        lookup: _lookupFavoriteMessage,
      ),
    );
  }

  Future<FavoriteSendResult> _lookupFavoriteMessage(
      Message message, FavoriteTarget target) async {
    final result = await ChatMessageSender().lookup(message, target);
    if (result.isSuccess &&
        result.message != null &&
        !isClosed &&
        _chatAccountID == OpenIM.iMManager.userID &&
        target.conversationID == conversationInfo.conversationID) {
      final local = messageList
          .firstWhereOrNull((item) => item.clientMsgID == result.clientMsgID);
      if (local != null) _delivery.sendSucceeded(local, result.message!);
    }
    return result;
  }

  Future<FavoriteSendResult> _sendFavoriteMessage(
      Message message, FavoriteTarget target) async {
    if (isClosed ||
        _chatAccountID != OpenIM.iMManager.userID ||
        target.conversationID != conversationInfo.conversationID) {
      return FavoriteSendResult(
        status: FavoriteSendStatus.failed,
        clientMsgID: message.clientMsgID,
        errorCode: 'CHAT_CLOSED',
        errorMessage: 'favoriteChatChanged'.tr,
      );
    }
    if (sendingMuted || isInvalidGroup) {
      return FavoriteSendResult(
        status: FavoriteSendStatus.failed,
        clientMsgID: message.clientMsgID,
        errorCode: 'SEND_FORBIDDEN',
        errorMessage: StrRes.youMuted,
      );
    }
    final scope = _repository.sessionScope;
    try {
      await _repository.requireAvailable();
    } catch (error) {
      return FavoriteSendResult(
          status: FavoriteSendStatus.failed,
          clientMsgID: message.clientMsgID,
          errorCode: error is FavoriteApiException
              ? error.code.toString()
              : 'CAPABILITY_UNAVAILABLE',
          errorMessage: error is FavoriteApiException
              ? error.message
              : 'favoriteSaveFailed'.tr);
    }
    if (isClosed ||
        !_repository.isSessionCurrent(scope) ||
        _chatAccountID != OpenIM.iMManager.userID ||
        target.conversationID != conversationInfo.conversationID) {
      return FavoriteSendResult(
          status: FavoriteSendStatus.failed,
          clientMsgID: message.clientMsgID,
          errorCode: 'CHAT_CLOSED',
          errorMessage: 'favoriteChatChanged'.tr);
    }
    final result = Completer<FavoriteSendResult>();
    try {
      message.status = MessageStatus.sending;
      await _sendMessage(
        message,
        resetInput: false,
        favoriteResult: (value) {
          if (!result.isCompleted) result.complete(value);
        },
      );
    } catch (error) {
      if (!result.isCompleted) {
        result.complete(ChatMessageSender.resultForError(error, message));
      }
    }
    if (!result.isCompleted) {
      result.complete(FavoriteSendResult(
        status: FavoriteSendStatus.unknown,
        clientMsgID: message.clientMsgID,
        errorCode: 'SEND_UNCONFIRMED',
        errorMessage: 'favoriteSendUnknown'.tr,
      ));
    }
    return result.future;
  }

  void failedResend(Message message) async {
    if (isClosed) return;
    // Retrying IM delivery does not retry a financial order and can duplicate
    // its card. The send form retries the original idempotent backend order.
    if (_isFundMessage(message) || message.clientMsgID == null) return;
    Logger.print('failedResend: ${message.clientMsgID}');
    if (message.status == MessageStatus.sending) {
      return;
    }
    final owner = OpenIM.iMManager.userID;
    final conversationID = conversationInfo.conversationID;
    try {
      final attemptID = await FavoriteRuntime.coordinator
          .pendingAttemptForMessage(message.clientMsgID!);
      if (isClosed ||
          owner != OpenIM.iMManager.userID ||
          conversationID != conversationInfo.conversationID) {
        return;
      }
      if (attemptID != null) {
        await _repository.requireAvailable();
        var result = await FavoriteRuntime.coordinator.retry(
          attemptID,
          onSend: _sendFavoriteMessage,
        );
        if (result.status == FavoriteSendStatus.unknown) {
          result = await FavoriteRuntime.coordinator
              .reconcile(attemptID, lookup: _lookupFavoriteMessage);
        }
        if (isClosed || owner != OpenIM.iMManager.userID) return;
        if (result.isSuccess) {
          // A restored success tombstone has no message body, but does confirm
          // that this original task was accepted. Never send it again.
          if (result.message?.clientMsgID == message.clientMsgID) {
            message.update(result.message!);
          }
          message.status = MessageStatus.succeeded;
          messageList.refresh();
        } else {
          IMViews.showToast(result.errorMessage ?? 'favoriteSendUnknown'.tr);
        }
        return;
      }
    } catch (error) {
      // Do not bypass an unreadable favorite journal with a raw SDK resend.
      if (!isClosed && owner == OpenIM.iMManager.userID) {
        IMViews.showToast(error is FavoriteApiException
            ? error.message
            : 'favoriteSendUnknown'.tr);
      }
      return;
    }
    _delivery.sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: message.clientMsgID!,
      value: true,
    ));

    Logger.print('failedResending: ${message.clientMsgID}');
    _sendMessage(message..status = MessageStatus.sending,
        addToUI: false, resetInput: false);
  }
}
