import 'dart:async';
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart' as sdk;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/notifications/message_notification_actions.dart';
import 'package:openim/core/notifications/message_notification_avatar_cache.dart';
import 'package:openim/core/notifications/message_notification_policy.dart';
import 'package:openim/core/notifications/message_notification_preferences.dart';
import 'package:openim/core/notifications/message_notification_runtime.dart';
import 'package:openim/core/notifications/message_notification_target.dart';
import 'package:openim/core/notifications/system_message_notifier.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    Get.locale = const Locale('zh', 'CN');
    Get.addTranslations(TranslationService().keys);
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });
  tearDown(Get.reset);

  test('first native notification is shown before its avatar becomes available',
      () async {
    final h = _Harness()..avatarURL = 'https://example.com/avatar.png';
    final avatar = h.avatars.waitFor(h.avatarURL!);
    await h.start();
    await h.runtime.receive(h.message('m1'));
    expect(h.notifier.shown, hasLength(1));
    expect(h.notifier.shown.single.avatarPath, isNull);
    expect(h.notifier.shown.single.presentation.body, 'body-m1');
    expect(avatar.isCompleted, isFalse);
    avatar.complete('/fake/avatar.png');
    await _flush();
    expect(h.notifier.shown, hasLength(2));
    expect(h.notifier.shown.last.avatarPath, '/fake/avatar.png');
    expect(h.notifier.shown.last.alert, isFalse);
    expect(h.notifier.shown.last.target.messageID, 'm1');
  });

  test('global mute skips every lookup in a 1000-message burst', () async {
    final h = _Harness();
    await h.start();
    h.user.globalRecvMsgOpt = 2;
    await Future.wait(
        List.generate(1000, (i) => h.runtime.receive(h.message('muted-$i'))));
    expect(h.lookups, 0);
    expect(h.notifier.shown, isEmpty);
  });
  test('duplicate live SDK deliveries do not show or look up twice', () async {
    final h = _Harness();
    await h.start();
    await Future.wait([
      h.runtime.receive(h.message('m1')),
      h.runtime.receive(h.message('m1')),
    ]);
    expect(h.lookups, 1);
    expect(h.notifier.shown, hasLength(1));
    await h.runtime.receive(h.message('m1'));
    expect(h.notifier.shown, hasLength(1));
  });

  test('older SDK lookup cannot overwrite a newer arrival notification',
      () async {
    final h = _Harness();
    final olderLookup = Completer<sdk.ConversationInfo>();
    var queries = 0;
    h.lookup = (target) => ++queries == 1
        ? olderLookup.future
        : Future.value(h.conversation(target));
    await h.start();
    final older = h.runtime.receive(h.message('m1'));
    await _flush();
    final newer = h.runtime.receive(h.message('m2'));
    await _flush();
    expect(queries, 1);
    olderLookup.complete(h.conversation(h.target('m1')));
    await Future.wait([older, newer]);
    expect(h.notifier.shown, hasLength(1),
        reason: 'Delayed lookup must not make the older arrival current');
    expect(h.notifier.shown.last.target.messageID, 'm2');
  });

  test('runtime applies active chat and freshly persisted app-state switches',
      () async {
    final h = _Harness()..activeConversationID = 'single-peer';
    await h.start();
    await h.runtime.receive(h.message('m1'));
    expect(h.notifier.shown, isEmpty);
    h.activeConversationID = null;
    await SpUtil().putBool('99chat_settings_self_notify_when_open', false);
    await h.runtime.receive(h.message('m2'));
    expect(h.notifier.shown, isEmpty);
    h.foreground = false;
    await SpUtil().putBool('99chat_settings_self_notify_when_closed', false);
    await h.runtime.receive(h.message('m3'));
    expect(h.notifier.shown, isEmpty);
    await SpUtil().putBool('99chat_settings_self_notify_when_closed', true);
    h.activeConversationID = 'single-peer'; // A stale route cannot hide push.
    await h.runtime.receive(h.message('m4'));
    expect(h.notifier.shown.single.target.messageID, 'm4');
  });

  test('background SDK alerts are independent of foreground sound switches',
      () async {
    final h = _Harness()..foreground = false;
    h.user.allowBeep = 0;
    h.user.allowVibration = 1;
    await h.start();
    await h.runtime.receive(h.message('m1'));
    expect(h.notifier.shown.single.sound, isFalse);
    expect(h.notifier.shown.single.vibration, isTrue);
    await SpUtil().putBool('99chat_settings_self_vibration', false);
    await h.runtime.receive(h.message('m2'));
    expect(h.notifier.shown.last.vibration, isTrue);
    h.user.globalRecvMsgOpt = 2;
    await h.runtime.receive(h.message('m3'));
    expect(h.notifier.shown, hasLength(2));
  });

  test('active chat receives only one foreground alert and no native banner',
      () async {
    final h = _Harness()..activeConversationID = 'single-peer';
    await SpUtil().putString('99chat_settings_self_message_sound', 'soft');
    await h.start();
    await h.runtime.receive(h.message('m1'));
    await _flush();
    expect(h.notifier.shown, isEmpty);
    expect(h.alerts, hasLength(1));
    expect(h.alerts.single.soundID, 'soft');
    expect(h.alerts.single.sound, isTrue);
    expect(h.alerts.single.vibration, isTrue);
    await h.runtime.receive(h.message('m1'));
    expect(h.alerts, hasLength(1));
  });

  test('banner off keeps independent foreground sound and vibration choices',
      () async {
    final h = _Harness();
    await SpUtil().putBool('99chat_settings_self_notify_when_open', false);
    await SpUtil().putBool('99chat_settings_self_message_sound_enabled', false);
    await h.start();
    await h.runtime.receive(h.message('m1'));
    expect(h.alerts.single.sound, isFalse);
    expect(h.alerts.single.vibration, isTrue);
    expect(h.notifier.shown, isEmpty);
    await SpUtil().putBool('99chat_settings_self_message_sound_enabled', true);
    await SpUtil().putBool('99chat_settings_self_vibration', false);
    // Old profile toggles do not shadow the explicit foreground settings.
    h.user.allowBeep = 0;
    await h.runtime.receive(h.message('m2'));
    expect(h.alerts.last.sound, isTrue);
    expect(h.alerts.last.vibration, isFalse);
  });

  test(
      'foreground native banner is silent to avoid a second sound or vibration',
      () async {
    final h = _Harness();
    await h.start();
    await h.runtime.receive(h.message('m1'));
    expect(h.alerts, hasLength(1));
    expect(h.notifier.shown.single.sound, isFalse);
    expect(h.notifier.shown.single.vibration, isFalse);
  });

  test('switching to background during native preparation cannot alert twice',
      () async {
    final h = _Harness();
    await h.start();
    final gate = Completer<void>();
    h.notifier.beforeInvalidate = gate.future;
    final arrival = h.runtime.receive(h.message('m1'));
    await _flush();
    expect(h.alerts, hasLength(1));
    h.foreground = false;
    gate.complete();
    await arrival;
    expect(h.notifier.shown.single.sound, isFalse);
    expect(h.notifier.shown.single.vibration, isFalse);
  });

  test('99Pay retries deduplicate their stable deposit notice ID', () async {
    final h = _Harness();
    await h.start();
    sdk.Message notice(String delivery, String noticeID) => h.message(delivery)
      ..sendID = '99Pay'
      ..ex = '{"depositNoticeID":"$noticeID"}';
    await h.runtime.receive(notice('first-sdk-id', 'deposit-1'));
    await h.runtime.receive(notice('second-sdk-id', 'deposit-1'));
    expect(h.lookups, 1);
    expect(h.notifier.shown, hasLength(1));
    await h.runtime.receive(notice('rollback-sdk-id', 'deposit-1-reversed'));
    expect(h.notifier.shown, hasLength(2));
  });

  test('muted conversation and active call suppress foreground alerts',
      () async {
    final h = _Harness();
    h.lookup = (target) async => h.conversation(target)..recvMsgOpt = 1;
    await h.start();
    await h.runtime.receive(h.message('m1'));
    expect(h.alerts, isEmpty);
    h.lookup = null;
    h.suppressed = true;
    await h.runtime.receive(h.message('m2'));
    expect(h.alerts, isEmpty);
  });

  test(
      'in-flight foreground alert cannot survive preference or account changes',
      () async {
    final h = _Harness();
    await h.start();
    await h.runtime.receive(h.message('m1'));
    expect(h.alerts.single.isCurrent(), isTrue);
    await SpUtil().putString('99chat_settings_self_message_sound', 'chime');
    MessageNotificationPreferences.notifyChanged('self');
    expect(h.alerts.single.isCurrent(), isFalse);
    expect(h.alertStops, 1);
    await h.runtime.receive(h.message('m2'));
    expect(h.alerts.last.soundID, 'chime');
    h.session = (accountID: 'other', sessionKey: 'new-session');
    expect(h.alerts.last.isCurrent(), isFalse);
    h.runtime.invalidateSession();
    expect(h.alertStops, 2);
  });

  for (final change in ['account', 'token']) {
    test('$change change blocks late SDK lookup from the previous session',
        () async {
      final h = _Harness();
      final result = Completer<sdk.ConversationInfo>();
      h.lookup = (_) => result.future;
      await h.start();
      final pending = h.runtime.receive(h.message('m1'));
      await _flush();
      h.session = (
        accountID: change == 'account' ? 'other' : 'self',
        sessionKey: 'renewed-session'
      );
      result.complete(h.conversation(h.target('m1')));
      await pending;
      expect(h.notifier.shown, isEmpty);
    });
  }

  test('cold-launch body tap queues until SDK sync and opens its SDK target',
      () async {
    final h = _Harness()..ready = false;
    h.notifier.launchResponse = h.response(h.target('m1'), id: 99);
    await h.runtime.initialize();
    expect(h.opened, isEmpty);
    expect(h.lookups, 0);
    h.ready = true;
    await h.runtime.onSessionReady();
    expect(h.opened.single.conversationID, 'single-peer');
    expect(h.opened.single.userID, 'peer');
    expect(h.notifier.permissions, 1);
    expect(h.errors, isEmpty);
  });

  test('native body tap resolves the correct group without sending a reply',
      () async {
    final h = _Harness();
    await h.start();
    await h.runtime.receive(h.message('group-m1', group: true));
    final shown = h.notifier.shown.single;
    expect(shown.target.sourceID, 'team');
    expect(shown.target.sessionType, sdk.ConversationType.superGroup);
    h.notifier.respond(h.response(shown.target, id: shown.id));
    await _flush();
    expect(h.opened.single.conversationID, 'group-team');
    expect(h.opened.single.groupID, 'team');
    expect(h.opened.single.userID, isNull);
    expect(h.sent, isEmpty);
    expect(h.notifier.cancelled, [shown.id]);
  });

  test('M1 reply completion and old callback cannot remove M2 or its avatar',
      () async {
    final h = _Harness();
    await h.start();
    await h.runtime.receive(h.message('m1'));
    final first = h.notifier.shown.single;
    final send = Completer<void>();
    h.onSend = (_, __) => send.future;
    final response = h.response(first.target,
        id: first.id,
        action: MessageNotificationActions.replyAction,
        input: 'same reply');
    h.notifier.respond(response);
    await h.sendStarted.future;
    h.avatarURL = 'https://example.com/m2.png';
    final avatar = h.avatars.waitFor(h.avatarURL!);
    await h.runtime.receive(h.message('m2'));
    expect(h.notifier.shown.last.id, first.id);
    final invalidations = h.notifier.invalidated.length;
    h.notifier.respond(response); // A delayed duplicate from replaced M1.
    await _flush();
    expect(h.notifier.invalidated.length, invalidations);
    send.complete();
    await _flush();
    expect(h.sent, ['same reply']);
    expect(h.notifier.cancelled, isEmpty);
    avatar.complete('/fake/m2.png');
    await _flush();
    expect(h.notifier.shown.last.target.messageID, 'm2');
    expect(h.notifier.shown.last.avatarPath, '/fake/m2.png');
    expect(h.notifier.shown.last.alert, isFalse);
  });

  test('avatar completion rereads privacy and cannot revive anonymous details',
      () async {
    final h = _Harness()..avatarURL = 'https://example.com/avatar.png';
    final avatar = h.avatars.waitFor(h.avatarURL!);
    await h.start();
    await h.runtime.receive(h.message('m1'));
    await SpUtil()
        .putString('99chat_settings_self_notify_open_preview', 'none');
    avatar.complete('/fake/avatar.png');
    await _flush();
    expect(h.notifier.shown, hasLength(1));
  });

  test('preference event invalidates native show without waiting for it',
      () async {
    final h = _Harness();
    await h.start();
    final show = Completer<void>();
    h.notifier.beforeShow = show.future;
    final pending = h.runtime.receive(h.message('m1'));
    await h.notifier.showStarted.future;
    final invalidations = h.notifier.invalidated.length;
    await SpUtil().putBool('99chat_settings_self_notify_when_open', false);

    MessageNotificationPreferences.notifyChanged('self');
    expect(h.notifier.invalidated, hasLength(invalidations + 1),
        reason: 'Native donation must be invalidated before show returns');
    expect(h.notifier.cancelled, isEmpty,
        reason: 'Cancellation follows the outstanding native show');
    show.complete();
    await pending;
    await _flush();

    expect(h.notifier.shown, isEmpty);
    expect(h.notifier.visible, isEmpty);
    expect(h.notifier.cancelled,
        [MessageNotificationRuntime.notificationID('self', 'single-peer')]);
  });

  test('preference event removes a banner and invalidates its pending avatar',
      () async {
    final h = _Harness()..avatarURL = 'https://example.com/avatar.png';
    final avatar = h.avatars.waitFor(h.avatarURL!);
    await h.start();
    await h.runtime.receive(h.message('m1'));
    final banner = h.notifier.shown.single;
    expect(h.notifier.visible[banner.id], isNotNull);
    await SpUtil()
        .putString('99chat_settings_self_notify_open_preview', 'none');

    MessageNotificationPreferences.notifyChanged('self');
    await _flush();
    expect(h.notifier.cancelled, [banner.id]);
    expect(h.notifier.visible, isEmpty);
    avatar.complete('/fake/avatar.png');
    await _flush();

    expect(h.notifier.shown, hasLength(1),
        reason: 'The old avatar must not restore a cancelled identity preview');
    expect(h.notifier.visible, isEmpty);
  });

  test('another account preference event does not invalidate a pending banner',
      () async {
    final h = _Harness();
    await h.start();
    final show = Completer<void>();
    h.notifier.beforeShow = show.future;
    final pending = h.runtime.receive(h.message('m1'));
    await h.notifier.showStarted.future;
    final invalidations = h.notifier.invalidated.length;
    await SpUtil().putBool('99chat_settings_other_notify_when_open', false);

    MessageNotificationPreferences.notifyChanged('other');
    expect(h.notifier.invalidated, hasLength(invalidations));
    show.complete();
    await pending;
    await _flush();

    expect(h.notifier.shown.single.target.accountID, 'self');
    expect(h.notifier.visible.values.single.target.messageID, 'm1');
    expect(h.notifier.cancelled, isEmpty);
  });

  test('privacy is rechecked after the asynchronous group member lookup',
      () async {
    final h = _Harness()..avatarURL = 'https://example.com/group.png';
    final avatar = h.avatars.waitFor(h.avatarURL!);
    final members = Completer<int?>();
    final lookupStarted = Completer<void>();
    h.members = (_) {
      lookupStarted.complete();
      return members.future;
    };
    await h.start();
    await h.runtime.receive(h.message('m1', group: true));
    avatar.complete('/fake/group.png');
    await lookupStarted.future;
    await SpUtil()
        .putString('99chat_settings_self_notify_open_preview', 'none');
    members.complete(7);
    await _flush();
    expect(h.notifier.shown, hasLength(1),
        reason: 'An avatar update must not reuse pre-await identity/content');
  });

  test('invalidation during initialization cannot revive the same credentials',
      () async {
    final h = _Harness();
    final initialize = Completer<void>();
    h.notifier.beforeInitialize = initialize.future;
    final pending = h.runtime.onSessionReady();
    await h.notifier.initializeStarted.future;
    // SDK cleanup and credential deletion may still be pending at this point.
    h.runtime.invalidateSession();
    initialize.complete();
    await pending;
    await h.runtime.receive(h.message('m1'));
    expect(h.notifier.shown, isEmpty);
    expect(h.lookups, 0);
  });

  test('simultaneous session-ready triggers initialize native session once',
      () async {
    final h = _Harness();
    final cancel = Completer<void>();
    h.notifier.beforeCancelAll = cancel.future;
    final first = h.runtime.onSessionReady();
    final second = h.runtime.onSessionReady();
    await h.notifier.cancelAllStarted.future;
    cancel.complete();
    await Future.wait([first, second]);
    expect(h.notifier.cancelAllCount, 1);
    expect(h.notifier.sessions, ['session-1']);
  });

  test('receive waits for first session cleanup before showing its banner',
      () async {
    final h = _Harness();
    final cancel = Completer<void>();
    h.notifier.beforeCancelAll = cancel.future;
    final ready = h.runtime.onSessionReady();
    await h.notifier.cancelAllStarted.future;
    final receive = h.runtime.receive(h.message('m1'));
    await _flush();
    expect(h.notifier.shown, isEmpty);
    cancel.complete();
    await Future.wait([ready, receive]);
    expect(h.notifier.shown.single.target.messageID, 'm1');
    expect(h.notifier.visible.values.single.target.messageID, 'm1');
  });

  test('late previous-account cleanup cannot clear the next account banner',
      () async {
    final h = _Harness();
    await h.start();
    final clear = Completer<void>();
    h.notifier.beforeClearSession = clear.future;
    h.runtime.invalidateSession();
    await h.notifier.clearSessionStarted.future;
    h.session = (accountID: 'other', sessionKey: 'other-session');
    final ready = h.runtime.onSessionReady();
    final receive = ready.then((_) => h.runtime.receive(h.message('m2')));
    await _flush();
    clear.complete();
    await receive;
    await _flush();
    expect(h.notifier.visible.values.single.target.accountID, 'other');
    expect(h.notifier.visible.values.single.target.messageID, 'm2');
  });

  test('late native show is guarded after account/token invalidation',
      () async {
    final h = _Harness();
    await h.start();
    final blocked = Completer<void>();
    h.notifier.beforeShow = blocked.future;
    final pending = h.runtime.receive(h.message('m1'));
    await h.notifier.showStarted.future;
    h.runtime.invalidateSession();
    h.session = (accountID: 'other', sessionKey: 'other-session');
    blocked.complete();
    await pending;
    await _flush();
    expect(h.notifier.shown, isEmpty);
  });

  test('logout cancels native state and late lookup/actions cannot affect it',
      () async {
    final h = _Harness();
    await h.start();
    final result = Completer<sdk.ConversationInfo>();
    h.lookup = (_) => result.future;
    final oldTarget = h.target('m1');
    final pending = h.runtime.receive(h.message('m1'));
    await _flush();
    final cancelAll = h.notifier.cancelAllCount;
    h.runtime.invalidateSession();
    h.session = null;
    result.complete(h.conversation(oldTarget));
    await pending;
    h.notifier.respond(h.response(oldTarget, id: 99));
    await _flush();
    expect(h.notifier.cancelAllCount, greaterThan(cancelAll));
    expect(h.notifier.clearedSessions, contains('session-1'));
    expect(h.notifier.shown, isEmpty);
    expect(h.opened, isEmpty);
    expect(h.sent, isEmpty);
  });

  test('closing is idempotent and no future notification or action is accepted',
      () async {
    final h = _Harness();
    await h.start();
    final target = h.target('m1');
    h.runtime.close();
    h.runtime.close();
    await h.runtime.receive(h.message('m1'));
    h.notifier.respond(h.response(target, id: 99));
    await h.runtime.onSessionReady();
    await _flush();
    expect(h.lookups, 0);
    expect(h.notifier.shown, isEmpty);
    expect(h.opened, isEmpty);
  });
}

class _Harness {
  _Harness() {
    runtime = MessageNotificationRuntime(
      notifier: notifier,
      currentSession: () => session,
      sdkReady: () => ready,
      isForeground: () => foreground,
      activeConversationID: () => activeConversationID,
      userInfo: () => user,
      suppressSound: () => suppressed,
      foregroundAlert: (
          {required soundID,
          required sound,
          required vibration,
          required isCurrent}) async {
        alerts.add((
          soundID: soundID,
          sound: sound,
          vibration: vibration,
          isCurrent: isCurrent
        ));
      },
      stopForegroundAlerts: () async {
        alertStops++;
      },
      avatars: avatars,
      groupMemberCount: (groupID) =>
          members?.call(groupID) ?? Future.value(null),
      loadConversation: (target) {
        lookups++;
        return lookup?.call(target) ?? Future.value(conversation(target));
      },
      openConversation: (conversation) async => opened.add(conversation),
      sendReply: (text, conversation) async {
        sent.add(text);
        if (!sendStarted.isCompleted) sendStarted.complete();
        await onSend?.call(text, conversation);
      },
      reportError: errors.add,
    );
    addTearDown(() async {
      runtime.close();
      avatars.finish();
      await _flush();
    });
  }

  final notifier = _FakeNotifier();
  final avatars = _FakeAvatars();
  final user = UserFullInfo(
      userID: 'self', allowBeep: 1, allowVibration: 1, globalRecvMsgOpt: 0);
  late final MessageNotificationRuntime runtime;
  MessageNotificationSession? session =
      (accountID: 'self', sessionKey: 'session-1');
  bool ready = true;
  bool foreground = true;
  bool suppressed = false;
  int alertStops = 0;
  final alerts = <({
    String soundID,
    bool sound,
    bool vibration,
    bool Function() isCurrent
  })>[];
  String? activeConversationID;
  String? avatarURL;
  int lookups = 0;
  final opened = <sdk.ConversationInfo>[];
  final sent = <String>[];
  final errors = <String>[];
  final sendStarted = Completer<void>();
  Future<sdk.ConversationInfo> Function(MessageNotificationTarget)? lookup;
  Future<void> Function(String, sdk.ConversationInfo)? onSend;
  Future<int?> Function(String)? members;
  Future<void> start() => runtime.onSessionReady();

  sdk.Message message(String id, {bool group = false}) => sdk.Message(
      clientMsgID: id,
      sendID: 'peer',
      recvID: session?.accountID ?? 'self',
      sessionType:
          group ? sdk.ConversationType.superGroup : sdk.ConversationType.single,
      groupID: group ? 'team' : null,
      contentType: sdk.MessageType.text,
      senderNickname: 'Alice',
      textElem: sdk.TextElem(content: 'body-$id'));

  MessageNotificationTarget target(String messageID, {bool group = false}) =>
      MessageNotificationTarget(
          accountID: session?.accountID ?? 'self',
          sessionKey: session?.sessionKey ?? 'session-1',
          conversationID: group ? 'group-team' : 'single-peer',
          sourceID: group ? 'team' : 'peer',
          sessionType: group
              ? sdk.ConversationType.superGroup
              : sdk.ConversationType.single,
          messageID: messageID);

  sdk.ConversationInfo conversation(MessageNotificationTarget target) =>
      sdk.ConversationInfo(
          conversationID: target.isSingleChat
              ? 'single-${target.sourceID}'
              : 'group-${target.sourceID}',
          conversationType: target.sessionType,
          userID: target.isSingleChat ? target.sourceID : null,
          groupID: target.isSingleChat ? null : target.sourceID,
          showName: target.isSingleChat ? 'Alice' : 'Team',
          recvMsgOpt: 0,
          faceURL: avatarURL);

  NotificationResponse response(MessageNotificationTarget target,
          {required int id, String? action, String? input}) =>
      NotificationResponse(
          notificationResponseType: action == null
              ? NotificationResponseType.selectedNotification
              : NotificationResponseType.selectedNotificationAction,
          id: id,
          payload: target.encode(),
          actionId: action,
          input: input);
}

class _FakeAvatars extends MessageNotificationAvatarCache {
  _FakeAvatars()
      : super(fetch: (_) async => throw StateError('No real network'));
  final pending = <String, Completer<String?>>{};
  Completer<String?> waitFor(String url) =>
      pending.putIfAbsent(url, Completer<String?>.new);
  @override
  Future<String?> resolve(String? url) =>
      pending[url]?.future ?? Future.value(null);
  void finish() {
    for (final result in pending.values) {
      if (!result.isCompleted) result.complete(null);
    }
  }
}

typedef _Shown = ({
  int id,
  MessageNotificationTarget target,
  MessageNotificationPresentation presentation,
  bool sound,
  bool vibration,
  String? avatarPath,
  bool alert
});

class _FakeNotifier extends SystemMessageNotifier {
  _FakeNotifier() : super(FlutterLocalNotificationsPlugin());
  final shown = <_Shown>[];
  final visible = <int, _Shown>{};
  final cancelled = <int>[];
  final invalidated = <({int id, String sessionKey})>[];
  final sessions = <String>[];
  final clearedSessions = <String?>[];
  int permissions = 0;
  int cancelAllCount = 0;
  NotificationResponse? launchResponse;
  late void Function(NotificationResponse) respond;
  final showStarted = Completer<void>();
  final initializeStarted = Completer<void>();
  final cancelAllStarted = Completer<void>();
  final clearSessionStarted = Completer<void>();
  Future<void>? beforeInitialize;
  Future<void>? beforeCancelAll;
  Future<void>? beforeClearSession;
  Future<void>? beforeShow;
  Future<void>? beforeInvalidate;
  @override
  Future<void> initialize(
      void Function(NotificationResponse) onResponse) async {
    if (!initializeStarted.isCompleted) initializeStarted.complete();
    await beforeInitialize;
    respond = onResponse;
    if (launchResponse != null) onResponse(launchResponse!);
  }

  @override
  Future<void> requestPermission() async => permissions++;
  @override
  Future<void> setSession(String sessionKey) async => sessions.add(sessionKey);
  @override
  Future<void> clearSession(String? sessionKey) async {
    clearedSessions.add(sessionKey);
    if (!clearSessionStarted.isCompleted) clearSessionStarted.complete();
    await beforeClearSession;
  }

  @override
  Future<void> invalidate(int id, String sessionKey) async {
    invalidated.add((id: id, sessionKey: sessionKey));
    await beforeInvalidate;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    visible.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    if (!cancelAllStarted.isCompleted) cancelAllStarted.complete();
    await beforeCancelAll;
    visible.clear();
  }

  @override
  Future<void> show(
      {required int id,
      required MessageNotificationTarget target,
      required MessageNotificationPresentation presentation,
      required bool sound,
      required bool vibration,
      String? avatarPath,
      bool alert = true,
      DateTime? timestamp,
      String? senderID,
      int? groupMemberCount,
      bool Function()? isCurrent}) async {
    if (!showStarted.isCompleted) showStarted.complete();
    await beforeShow;
    if (isCurrent?.call() == false) return;
    final notification = (
      id: id,
      target: target,
      presentation: presentation,
      sound: sound,
      vibration: vibration,
      avatarPath: avatarPath,
      alert: alert
    );
    shown.add(notification);
    visible[id] = notification;
  }
}
