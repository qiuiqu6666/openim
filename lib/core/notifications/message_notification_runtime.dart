import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart' as sdk;
import 'package:openim_common/openim_common.dart';

import 'message_notification_actions.dart';
import 'message_notification_avatar_cache.dart';
import 'message_notification_policy.dart';
import 'message_notification_preferences.dart';
import 'message_notification_target.dart';
import 'notification_lookup_pool.dart';
import 'system_message_notifier.dart';
import '../../services/fund/fund_deposit_notice.dart';

typedef MessageNotificationSession = ({String accountID, String sessionKey});
typedef ForegroundNotificationAlert = Future<void> Function({
  required String soundID,
  required bool sound,
  required bool vibration,
  required bool Function() isCurrent,
});

/// Coordinates SDK arrivals, native notification lifecycle and delayed actions.
class MessageNotificationRuntime {
  MessageNotificationRuntime({
    required this.notifier,
    required this.currentSession,
    required this.sdkReady,
    required this.isForeground,
    required this.activeConversationID,
    required this.userInfo,
    this.suppressSound,
    this.foregroundAlert,
    this.stopForegroundAlerts,
    this.groupMemberCount,
    required Future<sdk.ConversationInfo> Function(MessageNotificationTarget)
        loadConversation,
    required Future<void> Function(sdk.ConversationInfo) openConversation,
    required Future<void> Function(String, sdk.ConversationInfo) sendReply,
    required void Function(String) reportError,
    MessageNotificationAvatarCache? avatars,
  }) : _avatars = avatars ?? MessageNotificationAvatarCache() {
    _lookups = NotificationLookupPool(loadConversation);
    _actions = MessageNotificationActions(
      isCurrentSession: _owns,
      isReady: () =>
          !_closed &&
          _ready &&
          _allowed &&
          _sessionKey == currentSession()?.sessionKey &&
          sdkReady(),
      loadConversation: loadConversation,
      openConversation: openConversation,
      sendReply: sendReply,
      cancelNotification: cancelIfCurrent,
      reportError: reportError,
    );
    _preferencesSubscription =
        MessageNotificationPreferences.changes.listen(_preferencesChanged);
  }

  final SystemMessageNotifier notifier;
  final MessageNotificationSession? Function() currentSession;
  final bool Function() sdkReady;
  final bool Function() isForeground;
  final String? Function() activeConversationID;
  final UserFullInfo? Function() userInfo;
  final bool Function()? suppressSound;
  final ForegroundNotificationAlert? foregroundAlert;
  final Future<void> Function()? stopForegroundAlerts;
  final Future<int?> Function(String)? groupMemberCount;
  final MessageNotificationAvatarCache _avatars;
  late final MessageNotificationActions _actions;
  late final StreamSubscription<String> _preferencesSubscription;
  late final NotificationLookupPool _lookups;
  final Set<String> _seen = <String>{};
  final _versions = <int, int>{};
  final _targets = <int, MessageNotificationTarget>{};
  final _operations = <int, Future<void>>{};
  final _arrivals = <String, int>{};
  int _arrival = 0;
  int _version = 0;
  int _epoch = 0;
  Future<void> _lifecycleOperations = Future<void>.value();
  Future<void>? _initializing;
  Future<void>? _preparingSession;
  String? _sessionKey;
  String? _blockedSessionKey;
  bool _closed = false;
  bool _ready = false;
  bool _allowed = false;
  bool _permissionRequested = false;

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    await notifier.initialize(_onResponse);
    if (_closed) return;
    _ready = true;
  }

  void _onResponse(NotificationResponse response) {
    if (_closed) return;
    final target = MessageNotificationTarget.decode(response.payload);
    if (target == null || !_owns(target)) return;
    if (response.id != null && _sameNotification(target, response.id!)) {
      _versions.remove(response.id);
      unawaited(
          _safe(() => notifier.invalidate(response.id!, target.sessionKey)));
    }
    unawaited(_actions.handle(response.payload,
        actionId: response.actionId,
        input: response.input,
        notificationID: response.id));
  }

  bool _owns(MessageNotificationTarget target) {
    final session = currentSession();
    return !_closed &&
        session != null &&
        session.sessionKey != _blockedSessionKey &&
        target.accountID == session.accountID &&
        target.sessionKey == session.sessionKey;
  }

  Future<void> onSessionReady({bool authenticated = false}) {
    if (_closed) return Future<void>.value();
    final session = currentSession();
    if (session == null) return Future<void>.value();
    if (_blockedSessionKey == session.sessionKey) {
      if (!authenticated) return Future<void>.value();
      _blockedSessionKey = null;
    }
    if (!sdkReady()) return Future<void>.value();
    final pending = _preparingSession;
    if (pending != null) return pending;
    final epoch = _epoch;
    if (_sessionKey != session.sessionKey) _allowed = false;
    late final Future<void> preparing;
    preparing = _prepareSession(session, epoch).whenComplete(() {
      if (identical(_preparingSession, preparing)) _preparingSession = null;
      if (!_closed &&
          _epoch == epoch &&
          sdkReady() &&
          currentSession()?.sessionKey != session.sessionKey) {
        unawaited(_safe(() => onSessionReady()));
      }
    });
    _preparingSession = preparing;
    return preparing;
  }

  bool _sessionCurrent(MessageNotificationSession session, int epoch) =>
      !_closed &&
      _epoch == epoch &&
      currentSession() == session &&
      _blockedSessionKey != session.sessionKey &&
      sdkReady();

  Future<void> _prepareSession(
      MessageNotificationSession session, int epoch) async {
    if (!_sessionCurrent(session, epoch)) return;
    await initialize();
    if (!_sessionCurrent(session, epoch)) return;
    await _enqueueLifecycle(() async {
      if (!_sessionCurrent(session, epoch)) return;
      if (_sessionKey != session.sessionKey) {
        _seen.clear();
        _versions.clear();
        _targets.clear();
        _arrivals.clear();
        await notifier.cancelAll();
        if (!_sessionCurrent(session, epoch)) return;
        await notifier.setSession(session.sessionKey);
        if (!_sessionCurrent(session, epoch)) return;
        _sessionKey = session.sessionKey;
      }
      _allowed = true;
    });
    if (!_sessionCurrent(session, epoch)) return;
    if (!_permissionRequested && isForeground()) {
      _permissionRequested = true;
      await notifier.requestPermission();
    }
    if (_sessionCurrent(session, epoch)) {
      await _actions.processPending();
    }
  }

  Future<void> receive(sdk.Message message) async {
    final session = currentSession();
    final epoch = _epoch;
    if (_closed ||
        !sdkReady() ||
        userInfo()?.globalRecvMsgOpt == 2 ||
        session == null ||
        _blockedSessionKey == session.sessionKey ||
        message.contentType == null ||
        message.sendID == session.accountID ||
        message.contentType == sdk.MessageType.typing ||
        message.contentType! >= sdk.MessageType.notificationBegin) {
      return;
    }
    final source = message.sessionType == sdk.ConversationType.single
        ? message.sendID
        : message.groupID;
    if (source == null || source.isEmpty || message.sessionType == null) return;
    final messageID = message.clientMsgID ?? message.seq?.toString();
    if (messageID == null || messageID.isEmpty) return;
    final noticeID =
        fundDepositNoticeID(message, receiverID: session.accountID);
    final identity = noticeID == null ? messageID : 'deposit:$noticeID';
    final key = '${session.sessionKey}|$source|$identity';
    final sourceKey = '${session.sessionKey}|${message.sessionType}|$source';
    try {
      if (!_allowed || _sessionKey != session.sessionKey) {
        await onSessionReady();
      }
      if (!_sessionCurrent(session, epoch) || !_allowed) return;
      if (!_seen.add(key)) return;
      if (_seen.length > 512) _seen.remove(_seen.first);
      final arrival = ++_arrival;
      _arrivals[sourceKey] = arrival;
      final lookup = MessageNotificationTarget(
          accountID: session.accountID,
          sessionKey: session.sessionKey,
          conversationID: 'lookup',
          sourceID: source,
          sessionType: message.sessionType!);
      if (!lookup.isValid) return;
      final conversation = await _lookups.read(lookup);
      if (conversation == null || !_sessionCurrent(session, epoch)) return;
      final target = MessageNotificationTarget(
          accountID: session.accountID,
          sessionKey: session.sessionKey,
          conversationID: conversation.conversationID,
          sourceID: source,
          sessionType: message.sessionType!,
          messageID: messageID);
      if (!_owns(target) ||
          !sdkReady() ||
          !target.matches(conversation) ||
          _arrivals[sourceKey] != arrival) {
        return;
      }
      final foregroundAtDelivery = isForeground();
      if (foregroundAtDelivery &&
          MessageNotificationPolicy.accepts(
              message: message,
              conversation: conversation,
              currentUserID: session.accountID,
              globalRecvMsgOpt: userInfo()?.globalRecvMsgOpt)) {
        final preferences =
            MessageNotificationPreferences.read(session.accountID);
        bool alertCurrent() {
          final fresh = MessageNotificationPreferences.read(session.accountID);
          return _owns(target) &&
              _allowed &&
              sdkReady() &&
              isForeground() &&
              _arrivals[sourceKey] == arrival &&
              suppressSound?.call() != true &&
              userInfo()?.globalRecvMsgOpt != 2 &&
              preferences.messageSoundEnabled == fresh.messageSoundEnabled &&
              preferences.vibration == fresh.vibration &&
              preferences.messageSound == fresh.messageSound;
        }

        if (alertCurrent()) {
          // Alert choices remain usable with banners off and in the active chat.
          // Never ask the native foreground banner to alert a second time.
          unawaited(_safe(() async => foregroundAlert?.call(
              soundID: preferences.messageSound,
              sound: preferences.messageSoundEnabled,
              vibration: preferences.vibration,
              isCurrent: alertCurrent)));
        }
      }
      final presentation = _present(message, conversation, session.accountID);
      if (presentation == null) return;
      final id = notificationID(session.accountID, conversation.conversationID);
      final version = ++_version;
      _versions[id] = version;
      _targets[id] = target;
      await _show(id, version, target, presentation, message, conversation,
          allowNativeAlert: !foregroundAtDelivery);
      if (presentation.avatarURL != null) {
        unawaited(_updateAvatar(id, version, target, message, conversation,
            presentation.avatarURL!));
      }
    } catch (error) {
      Logger.print('Message notification unavailable: ${error.runtimeType}',
          onlyConsole: true);
    }
  }

  MessageNotificationPresentation? _present(sdk.Message message,
          sdk.ConversationInfo conversation, String accountID) =>
      MessageNotificationPolicy.present(
          message: message,
          conversation: conversation,
          currentUserID: accountID,
          isForeground: isForeground(),
          activeConversationID: activeConversationID(),
          preferences: MessageNotificationPreferences.read(accountID),
          globalRecvMsgOpt: userInfo()?.globalRecvMsgOpt);

  Future<void> _show(
      int id,
      int version,
      MessageNotificationTarget target,
      MessageNotificationPresentation presentation,
      sdk.Message message,
      sdk.ConversationInfo conversation,
      {String? avatarPath,
      bool alert = true,
      bool allowNativeAlert = true,
      int? memberCount}) async {
    bool current() => _owns(target) && _allowed && _versions[id] == version;
    if (!current()) return;
    await _enqueue(id, () async {
      if (!current()) return;
      final fresh = _present(message, conversation, target.accountID);
      if (fresh == null ||
          (avatarPath != null && fresh.avatarURL != presentation.avatarURL)) {
        return;
      }
      final user = userInfo();
      bool stillCurrent() =>
          current() &&
          _samePresentation(
              fresh, _present(message, conversation, target.accountID));
      await notifier.invalidate(id, target.sessionKey);
      if (!stillCurrent()) return;
      await notifier.show(
          id: id,
          target: target,
          presentation: fresh,
          sound: allowNativeAlert &&
              !isForeground() &&
              fresh.enableSound &&
              user?.allowBeep != 0 &&
              suppressSound?.call() != true,
          vibration: allowNativeAlert &&
              !isForeground() &&
              fresh.enableVibration &&
              user?.allowVibration != 0 &&
              suppressSound?.call() != true,
          avatarPath: avatarPath,
          alert: alert,
          timestamp: message.sendTime == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(message.sendTime! * 1000),
          isCurrent: stillCurrent,
          senderID: message.sendID,
          groupMemberCount: memberCount);
    });
  }

  bool _samePresentation(MessageNotificationPresentation expected,
          MessageNotificationPresentation? current) =>
      current != null &&
      expected.title == current.title &&
      expected.body == current.body &&
      expected.avatarURL == current.avatarURL &&
      expected.senderName == current.senderName &&
      expected.isGroup == current.isGroup &&
      expected.showReply == current.showReply &&
      expected.enableSound == current.enableSound &&
      expected.enableVibration == current.enableVibration &&
      expected.soundID == current.soundID;

  Future<void> _updateAvatar(
      int id,
      int version,
      MessageNotificationTarget target,
      sdk.Message message,
      sdk.ConversationInfo conversation,
      String url) async {
    await _safe(() async {
      final path = await _avatars.resolve(url);
      if (path == null || !_owns(target) || _versions[id] != version) return;
      final members = !target.isSingleChat
          ? await groupMemberCount?.call(target.sourceID)
          : null;
      if (!_owns(target) || _versions[id] != version) return;
      final presentation = _present(message, conversation, target.accountID);
      if (presentation == null || presentation.avatarURL != url) return;
      await _show(id, version, target, presentation, message, conversation,
          avatarPath: path, alert: false, memberCount: members);
    });
  }

  bool _sameNotification(MessageNotificationTarget target, int id) {
    final visible = _targets[id];
    return visible == null ||
        (visible.accountID == target.accountID &&
            visible.sessionKey == target.sessionKey &&
            visible.conversationID == target.conversationID &&
            visible.messageID == target.messageID);
  }

  void _preferencesChanged(String accountID) {
    if (_closed || currentSession()?.accountID != accountID) return;
    if (stopForegroundAlerts != null) unawaited(_safe(stopForegroundAlerts!));
    for (final entry in _targets.entries.toList()) {
      if (!_owns(entry.value)) continue;
      _versions.remove(entry.key);
      // Do not wait behind show: the iOS donor itself may be in flight.
      unawaited(
          _safe(() => notifier.invalidate(entry.key, entry.value.sessionKey)));
      unawaited(_safe(() => cancelIfCurrent(entry.value, entry.key)));
    }
  }

  Future<void> cancelIfCurrent(MessageNotificationTarget target, int id) =>
      _enqueue(id, () async {
        if (!_owns(target) || !_sameNotification(target, id)) return;
        _versions.remove(id);
        await notifier.invalidate(id, target.sessionKey);
        if (!_owns(target) || !_sameNotification(target, id)) return;
        await notifier.cancel(id);
        if (_sameNotification(target, id)) _targets.remove(id);
      });

  Future<void> _enqueue(int id, Future<void> Function() operation) {
    final previous = _operations[id] ?? Future<void>.value();
    late final Future<void> pending;
    pending = previous
        .then((_) => operation(), onError: (_) => operation())
        .whenComplete(() {
      if (identical(_operations[id], pending)) _operations.remove(id);
    });
    _operations[id] = pending;
    return pending;
  }

  void invalidateSession() {
    _lookups.clear();
    final epoch = ++_epoch;
    if (stopForegroundAlerts != null) unawaited(_safe(stopForegroundAlerts!));
    _blockedSessionKey = currentSession()?.sessionKey;
    _preparingSession = null;
    _allowed = false;
    _seen.clear();
    _versions.clear();
    _targets.clear();
    _arrivals.clear();
    _actions.clearPending();
    final oldKey = _sessionKey;
    _sessionKey = null;
    unawaited(_safe(() => _enqueueLifecycle(() async {
          await notifier.clearSession(oldKey);
          if (_epoch == epoch && !_allowed) await notifier.cancelAll();
        })));
  }

  Future<void> _enqueueLifecycle(Future<void> Function() operation) {
    final pending = _lifecycleOperations.then((_) => operation(),
        onError: (_) => operation());
    _lifecycleOperations = pending.then((_) {}, onError: (_) {});
    return pending;
  }

  void close() {
    if (_closed) return;
    invalidateSession();
    _closed = true;
    unawaited(_preferencesSubscription.cancel());
    _actions.close();
  }

  static int notificationID(String accountID, String conversationID) {
    final bytes =
        sha256.convert(utf8.encode('$accountID|$conversationID')).bytes;
    return ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) &
        0x7fffffff;
  }

  Future<void> _safe(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      Logger.print('Notification operation unavailable: ${error.runtimeType}',
          onlyConsole: true);
    }
  }
}
