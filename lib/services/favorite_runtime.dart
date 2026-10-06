import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../pages/favorites/data/favorite_sync_binding.dart';
import '../pages/contacts/select_contacts/select_contacts_logic.dart';
import '../routes/app_navigator.dart';
import 'favorite_batch_sender.dart';
import 'favorite_repository.dart';
import 'favorite_send_coordinator.dart';

/// One account-scoped repository shared by Mine and the current chat picker.
class FavoriteRuntime {
  FavoriteRuntime._();

  static FavoriteRepository? _repository;
  static FavoriteSendCoordinator? _coordinator;
  static FavoriteBatchSender? _batchSender;
  static FavoriteSyncBinding? _syncBinding;
  static Stream<String>? _businessNotifications;
  static Stream<void>? _reconnected;

  static FavoriteRepository get repository {
    final value = _repository ??= FavoriteRepository.instance;
    _attachSync(value);
    return value;
  }

  static FavoriteSendCoordinator get coordinator =>
      _coordinator ??= FavoriteSendCoordinator(repository: repository);
  static FavoriteBatchSender get batchSender =>
      _batchSender ??= FavoriteBatchSender(
          repository: repository,
          sendItem: (item, target, attemptID) =>
              coordinator.send(item, target, sendAttemptID: attemptID));

  static void resetSession() {
    _syncBinding?.dispose();
    _syncBinding = null;
    _repository?.resetSession();
    _coordinator?.resetSession();
    _batchSender?.resetSession();
  }

  /// The SDK listener owner supplies streams; the runtime never replaces SDK
  /// listeners or creates the repository merely because an unrelated hint arrives.
  static void bindSync({
    required Stream<String> businessNotifications,
    required Stream<void> reconnected,
  }) {
    detachSync();
    _businessNotifications = businessNotifications;
    _reconnected = reconnected;
    final value = _repository;
    if (value != null) _attachSync(value);
  }

  static void _attachSync(FavoriteRepository value) {
    if (_syncBinding != null || _businessNotifications == null) return;
    _syncBinding = FavoriteSyncBinding(
      synchronize: value.syncChanges,
      sessionScope: () => value.sessionScope,
      isSessionCurrent: value.isSessionCurrent,
      notifications: _businessNotifications,
      reconnected: _reconnected,
    );
  }

  static void detachSync() {
    _syncBinding?.dispose();
    _syncBinding = null;
    _businessNotifications = null;
    _reconnected = null;
  }

  static Future<FavoriteSendResult> sendToConversation(
          BuildContext context, FavoriteItem item) =>
      sendItemsToConversation(context, [item]);

  static Future<FavoriteSendResult> sendItemsToConversation(
          BuildContext context, List<FavoriteItem> items) =>
      batchSender.send(items,
          selectTargets: () => _selectTargets(context, items));

  static Future<void> cancelSendItems(
          BuildContext context, List<FavoriteItem> items) =>
      batchSender.cancel(items);

  static Future<List<FavoriteTarget>?> _selectTargets(
      BuildContext context, List<FavoriteItem> items) async {
    final owner = DataSp.userID;
    final selected = await AppNavigator.startSelectContacts(
      action: SelAction.forward,
      ex: items.length == 1
          ? (items.single.title.isNotEmpty
              ? items.single.title
              : items.single.summary)
          : '收藏 (${items.length})',
    );
    if (selected == null) {
      return null;
    }
    if (!context.mounted || owner != DataSp.userID) {
      throw const FavoriteApiException('SESSION_CHANGED', '登录状态已改变，请重新打开收藏');
    }
    final contacts = selected is Map ? selected['checkedList'] : null;
    if (contacts is! Iterable || contacts.isEmpty) {
      return null;
    }
    final targets = <FavoriteTarget>[];
    for (final contact in contacts) {
      if (owner != DataSp.userID) {
        throw const FavoriteApiException('SESSION_CHANGED', '登录状态已改变');
      }
      try {
        final user =
            IMUtils.emptyStrToNull(IMUtils.convertCheckedToUserID(contact));
        final group =
            IMUtils.emptyStrToNull(IMUtils.convertCheckedToGroupID(contact));
        if ((user != null) == (group != null)) {
          throw const FormatException('Invalid selected destination');
        }
        final conversation = contact is ConversationInfo
            ? contact
            : await OpenIM.iMManager.conversationManager.getOneConversation(
                sourceID: user ?? group!,
                sessionType: user != null
                    ? ConversationType.single
                    : contact is GroupInfo &&
                            // Legacy group conversations still need their
                            // original type when resolving an existing chat.
                            // ignore: deprecated_member_use
                            contact.groupType == GroupType.general
                        // ignore: deprecated_member_use
                        ? ConversationType.group
                        : ConversationType.superGroup,
              );
        if (owner != DataSp.userID) {
          throw const FavoriteApiException('SESSION_CHANGED', '登录状态已改变');
        }
        final target = FavoriteTarget(
          conversationID: conversation.conversationID,
          userID: user,
          groupID: group,
          displayName: SelectContactsLogic.parseName(contact),
        );
        targets.add(target);
      } on FavoriteApiException {
        rethrow;
      } catch (_) {
        throw const FavoriteApiException(
            'TARGET_UNAVAILABLE', '无法打开所选会话，请重新选择');
      }
    }
    return targets;
  }
}
