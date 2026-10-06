import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart' as sdk;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/notifications/message_notification_actions.dart';
import 'package:openim/core/notifications/message_notification_policy.dart';
import 'package:openim/core/notifications/message_notification_sound.dart';
import 'package:openim/core/notifications/message_notification_target.dart';
import 'package:openim/core/notifications/system_message_notifier.dart';
import 'package:openim_common/openim_common.dart';

// Exercise FLN 18.0.1's actual Dart channel serializers, rather than replacing
// SystemMessageNotifier or notification-details objects with a fake notifier.
const _plugin = MethodChannel('dexterous.com/flutter/local_notifications');
const _bridge = MethodChannel('openim_chat_notifications');
const _logo = 'assets/img/99chat_logo.png';
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4X8AAAAASUVORK5CYII=');

MessageNotificationTarget _target({bool group = false}) =>
    MessageNotificationTarget(
      accountID: 'self',
      sessionKey: 'account-token-fingerprint',
      conversationID: group ? 'group-team' : 'single-peer',
      sourceID: group ? 'team' : 'peer',
      sessionType:
          group ? sdk.ConversationType.superGroup : sdk.ConversationType.single,
      messageID: 'sdk-message-1',
    );

MessageNotificationPresentation _presentation({
  bool group = false,
  bool reply = true,
  String soundID = MessageNotificationSoundIds.defaultId,
}) =>
    MessageNotificationPresentation(
      title: group ? 'Team' : 'Alice',
      body: group ? 'Bob: SDK message' : 'SDK message',
      avatarURL: 'https://example.invalid/avatar.png',
      isGroup: group,
      senderName: group ? 'Bob' : 'Alice',
      showReply: reply,
      enableSound: true,
      enableVibration: true,
      soundID: soundID,
    );

Map<Object?, Object?> _map(Object? value) => value! as Map<Object?, Object?>;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _Channels channels;

  setUp(() {
    Get.locale = const Locale('zh', 'CN');
    Get.addTranslations(TranslationService().keys);
    channels = _Channels(binding);
  });
  tearDown(() {
    channels.dispose();
    debugDefaultTargetPlatformOverride = null;
    Get.reset();
  });

  test('Android initializes its small app icon without a background engine',
      () async {
    final notifier = channels.use(TargetPlatform.android);
    await notifier.initialize((_) {});
    final args = channels.arguments('initialize');
    expect(args['defaultIcon'], '@mipmap/ic_launcher');
    expect(args.containsKey('dispatcher_handle'), isFalse);
    expect(args.containsKey('callback_handle'), isFalse);
    expect(channels.bridgeCalls, isEmpty);
  });

  test('Android serializes single-chat MessagingStyle and cached file avatar',
      () async {
    final notifier = channels.use(TargetPlatform.android);
    final timestamp = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    await _show(notifier, avatarPath: '/cache/alice.png', timestamp: timestamp);
    final args = channels.arguments('show');
    final android = _map(args['platformSpecifics']);
    final style = _map(android['styleInformation']);
    final message = _map((style['messages']! as List).single);
    final sender = _map(message['person']);
    expect(args['id'], 42);
    expect(args['payload'], _target().encode());
    expect(android['style'], AndroidNotificationStyle.messaging.index);
    expect(style['groupConversation'], isFalse);
    expect(style['conversationTitle'], 'Alice');
    expect(_map(style['person'])['key'], 'self');
    expect(_map(style['person'])['name'], 'Me');
    expect(message['text'], 'SDK message');
    expect(message['timestamp'], timestamp.millisecondsSinceEpoch);
    expect(sender['name'], 'Alice');
    expect(sender['icon'], '/cache/alice.png');
    expect(sender['iconSource'], 1); // FLN 18 bitmapFilePath.
    expect(android['largeIcon'], '/cache/alice.png');
    expect(android['largeIconBitmapSource'], 1); // FLN 18 filePath.
    expect(channels.assetReads, 0);
  });

  test('Android group style preserves group title and real sender identity',
      () async {
    final notifier = channels.use(TargetPlatform.android);
    await _show(notifier,
        group: true, avatarPath: '/cache/team.png', senderID: 'bob');
    final style = _map(_map(
        channels.arguments('show')['platformSpecifics'])['styleInformation']);
    final message = _map((style['messages']! as List).single);
    expect(style['groupConversation'], isTrue);
    expect(style['conversationTitle'], 'Team');
    // MessagingStyle renders the sender itself; the policy prefix is removed.
    expect(message['text'], 'SDK message');
    expect(_map(message['person'])['name'], 'Bob');
    expect(_map(message['person'])['key'], 'bob');
    expect(_map(message['person'])['icon'], '/cache/team.png');
  });

  test('Android missing avatars use the platform logo and load its bytes once',
      () async {
    final notifier = channels.use(TargetPlatform.android);
    await _show(notifier);
    await _show(notifier);
    expect(channels.assetReads, 1);
    for (final call in channels.pluginCalls.where((c) => c.method == 'show')) {
      final android = _map(_map(call.arguments)['platformSpecifics']);
      final style = _map(android['styleInformation']);
      final sender = _map(_map((style['messages']! as List).single)['person']);
      expect(android['largeIcon'], orderedEquals(_png));
      expect(android['largeIconBitmapSource'], 2); // FLN 18 byteArray.
      expect(sender['icon'], _logo);
      expect(sender['iconSource'], 3); // FLN 18 flutterBitmapAsset.
    }
  });

  test(
      'Android requests heads-up priority and separate sound/vibration channels',
      () async {
    final notifier = channels.use(TargetPlatform.android);
    for (final sound in [false, true]) {
      for (final vibration in [false, true]) {
        await _show(notifier, sound: sound, vibration: vibration);
        final android = _map(channels.arguments('show')['platformSpecifics']);
        expect(
            android['channelId'],
            sound
                ? 'chat_messages_v2_preview000_v${vibration ? 1 : 0}'
                : 'chat_messages_v2_silent_v${vibration ? 1 : 0}');
        expect(android['importance'], Importance.max.value);
        expect(android['priority'], Priority.high.value);
        expect(android['category'], 'msg'); // Android CATEGORY_MESSAGE.
        expect(android['visibility'], NotificationVisibility.private.index);
        expect(android['playSound'], sound);
        expect(android['enableVibration'], vibration);
      }
    }
  });

  test(
      'Android reply uses free-form RemoteInput and the existing foreground app',
      () async {
    final notifier = channels.use(TargetPlatform.android);
    await _show(notifier);
    final android = _map(channels.arguments('show')['platformSpecifics']);
    final action = _map((android['actions']! as List).single);
    final input = _map((action['inputs']! as List).single);
    expect(action['id'], MessageNotificationActions.replyAction);
    expect(action['showsUserInterface'], isTrue);
    expect(action['allowGeneratedReplies'], isTrue);
    expect(action['cancelNotification'], isFalse);
    expect(input['allowFreeFormInput'], isTrue);
    expect(input['label'], StrRes.reply);
  });

  test('each chosen sound has a distinct Android channel and raw resource',
      () async {
    final notifier = channels.use(TargetPlatform.android);
    final channelIDs = <Object?>{};
    for (final id in MessageNotificationSoundIds.optionIds) {
      await _show(notifier, soundID: id);
      final android = _map(channels.arguments('show')['platformSpecifics']);
      channelIDs.add(android['channelId']);
      expect(android['sound'], 'chat_message_$id');
      expect(android['soundSource'], 0); // FLN raw resource.
    }
    expect(channelIDs, hasLength(7));
  });

  test('each chosen sound reaches iOS ordinary and avatar notification paths',
      () async {
    final notifier = channels.use(TargetPlatform.iOS);
    for (final id in MessageNotificationSoundIds.optionIds) {
      await _show(notifier, soundID: id);
      expect(_map(channels.arguments('show')['platformSpecifics'])['sound'],
          'chat_message_$id.wav');
      await _show(notifier, soundID: id, avatarPath: '/cache/alice.png');
      final bridge = _map(channels.bridgeCalls.last.arguments);
      expect(bridge['soundName'], 'chat_message_$id.wav');
    }
  });

  test('disabled quick reply removes actions on Android and category on iOS',
      () async {
    var notifier = channels.use(TargetPlatform.android);
    await _show(notifier, reply: false);
    expect(
        _map(channels.arguments('show')['platformSpecifics'])
            .containsKey('actions'),
        isFalse);
    notifier = channels.use(TargetPlatform.iOS);
    await _show(notifier, reply: false);
    expect(
        _map(channels.arguments('show')['platformSpecifics'])[
            'categoryIdentifier'],
        isNull);
  });

  test(
      'Android silent avatar update retains its channel and cannot alert twice',
      () async {
    final notifier = channels.use(TargetPlatform.android);
    await _show(notifier);
    final first = _map(channels.arguments('show')['platformSpecifics']);
    await _show(notifier, avatarPath: '/cache/alice.png', alert: false);
    final update = _map(channels.arguments('show')['platformSpecifics']);
    expect(update['channelId'], first['channelId']);
    expect(update['onlyAlertOnce'], isTrue);
    expect(update['silent'], isTrue);
    expect(channels.arguments('show')['id'], 42);
  });

  test(
      'iOS installs foreground text-reply category without prompting permission',
      () async {
    final notifier = channels.use(TargetPlatform.iOS);
    await notifier.initialize((_) {});
    final args = channels.arguments('initialize');
    expect(args['requestAlertPermission'], isFalse);
    expect(args['requestBadgePermission'], isFalse);
    expect(args['requestSoundPermission'], isFalse);
    final category = _map((args['notificationCategories']! as List).single);
    final action = _map((category['actions']! as List).single);
    expect(category['identifier'], SystemMessageNotifier.replyCategory);
    expect(action['type'], 'text');
    expect(action['identifier'], MessageNotificationActions.replyAction);
    expect(action['buttonTitle'], StrRes.send);
    expect(action['options'],
        [1 << DarwinNotificationActionOption.foreground.index]);
    expect(args.containsKey('dispatcher_handle'), isFalse);
  });

  test('iOS cold-launch input and payload reach the existing response callback',
      () async {
    final notifier = channels.use(TargetPlatform.iOS);
    channels.launchDetails = {
      'notificationLaunchedApp': true,
      'notificationResponse': {
        'notificationId': 42,
        'actionId': MessageNotificationActions.replyAction,
        'input': 'Offline fake reply',
        'payload': _target().encode(),
        'notificationResponseType':
            NotificationResponseType.selectedNotificationAction.index,
      },
    };
    final responses = <NotificationResponse>[];
    await notifier.initialize(responses.add);
    expect(responses, hasLength(1));
    expect(responses.single.id, 42);
    expect(responses.single.input, 'Offline fake reply');
    expect(responses.single.actionId, MessageNotificationActions.replyAction);
    expect(responses.single.payload, _target().encode());
  });

  test('iOS without avatar uses ordinary OS notification and reply category',
      () async {
    final notifier = channels.use(TargetPlatform.iOS);
    await _show(notifier);
    final args = channels.arguments('show');
    final ios = _map(args['platformSpecifics']);
    expect(channels.bridgeCalls, isEmpty);
    expect(args['payload'], _target().encode());
    expect(ios['categoryIdentifier'], SystemMessageNotifier.replyCategory);
    expect(ios['threadIdentifier'], 'single-peer');
    expect(ios['attachments'], isNull);
    expect(ios['presentBanner'], isTrue);
    expect(ios['sound'], 'chat_message_preview000.wav');
  });

  test('handled iOS communication notification never duplicates FLN fallback',
      () async {
    final notifier = channels.use(TargetPlatform.iOS);
    await _show(notifier,
        group: true,
        avatarPath: '/cache/team.png',
        senderID: 'bob',
        groupMemberCount: 13);
    final args = channels.bridgeArguments('showCommunicationNotification');
    expect(args['sessionKey'], _target(group: true).sessionKey);
    expect(args['conversationID'], 'group-team');
    expect(args['payload'], _target(group: true).encode());
    expect(args['categoryIdentifier'], SystemMessageNotifier.replyCategory);
    expect(args['senderID'], 'bob');
    expect(args['groupMemberCount'], 13);
    expect(args['conversationAvatarPath'], '/cache/team.png');
    expect(args['isGroup'], isTrue);
    expect(channels.pluginCalls, isEmpty);
  });

  for (final failure in ['false', 'platform-error', 'missing-plugin']) {
    test('iOS communication $failure safely falls back to ordinary FLN',
        () async {
      final notifier = channels.use(TargetPlatform.iOS);
      channels.bridgeReply = (_) async {
        if (failure == 'platform-error') {
          throw PlatformException(code: 'UNAVAILABLE');
        }
        if (failure == 'missing-plugin') throw MissingPluginException();
        return false;
      };
      await _show(notifier, avatarPath: '/cache/alice.png');
      expect(channels.bridgeCalls, hasLength(1));
      final args = channels.arguments('show');
      expect(args['id'], 42);
      expect(args['title'], 'Alice');
      expect(args['payload'], _target().encode());
      expect(_map(args['platformSpecifics'])['categoryIdentifier'],
          SystemMessageNotifier.replyCategory);
    });
  }

  test('iOS avatar update reuses its ID with no banner or sound', () async {
    final notifier = channels.use(TargetPlatform.iOS);
    await _show(notifier);
    await _show(notifier, avatarPath: '/cache/alice.png', alert: false);
    final update = channels.bridgeArguments('showCommunicationNotification');
    expect(update['id'], channels.arguments('show')['id']);
    expect(update['alert'], isFalse);
    expect(update['playSound'], isFalse);
    expect(update['presentSound'], isFalse);
    expect(update['presentBanner'], isFalse);
    expect(update['presentList'], isTrue);
    expect(channels.pluginCalls.where((c) => c.method == 'show'), hasLength(1));
  });

  test('iOS unsuccessful avatar update falls back silently at passive level',
      () async {
    final notifier = channels.use(TargetPlatform.iOS);
    channels.bridgeReply = (_) async => false;
    await _show(notifier, avatarPath: '/cache/alice.png', alert: false);
    final ios = _map(channels.arguments('show')['platformSpecifics']);
    expect(ios['presentAlert'], isFalse);
    expect(ios['presentBanner'], isFalse);
    expect(ios['presentSound'], isFalse);
    expect(ios['sound'], isNull);
    expect(ios['presentList'], isTrue);
    expect(ios['interruptionLevel'], InterruptionLevel.passive.index);
  });

  test('session change while iOS bridge waits cannot issue an old fallback',
      () async {
    final notifier = channels.use(TargetPlatform.iOS);
    final bridgeResult = Completer<Object?>();
    channels.bridgeReply = (_) => bridgeResult.future;
    var current = true;
    final pending = _show(notifier,
        avatarPath: '/cache/alice.png', isCurrent: () => current);
    await Future<void>.delayed(Duration.zero);
    expect(channels.bridgeCalls, hasLength(1));
    current = false;
    bridgeResult.complete(false);
    await pending;
    expect(channels.pluginCalls, isEmpty);
  });

  test('inactive request never reads a fallback logo or calls either channel',
      () async {
    final notifier = channels.use(TargetPlatform.android);
    await _show(notifier, isCurrent: () => false);
    expect(channels.assetReads, 0);
    expect(channels.pluginCalls, isEmpty);
    expect(channels.bridgeCalls, isEmpty);
  });

  test('session change during fallback asset read prevents stale Android show',
      () async {
    final notifier = channels.use(TargetPlatform.android);
    final image = Completer<ByteData?>();
    channels.assetReply = () => image.future;
    var current = true;
    final pending = _show(notifier, isCurrent: () => current);
    await Future<void>.delayed(Duration.zero);
    expect(channels.assetReads, 1);
    current = false;
    image.complete(ByteData.sublistView(_png));
    await pending;
    expect(channels.pluginCalls, isEmpty);
  });

  test('iOS forwards captured session invalidation and native notification ID',
      () async {
    final notifier = channels.use(TargetPlatform.iOS);
    await notifier.setSession('new-scope');
    await notifier.invalidate(42, 'new-scope');
    await notifier.clearSession('old-scope');
    expect(channels.bridgeCalls.map((c) => c.method),
        ['setSession', 'invalidateNotification', 'clearSession']);
    expect(channels.bridgeArguments('setSession')['sessionKey'], 'new-scope');
    expect(channels.bridgeArguments('invalidateNotification'),
        {'sessionKey': 'new-scope', 'id': 42});
    expect(channels.bridgeArguments('clearSession')['sessionKey'], 'old-scope');
  });

  test('notification permission is requested explicitly on the active platform',
      () async {
    await channels.use(TargetPlatform.android).requestPermission();
    expect(
        channels.pluginCalls.single.method, 'requestNotificationsPermission');
    await channels.use(TargetPlatform.iOS).requestPermission();
    expect(channels.pluginCalls.last.method, 'requestPermissions');
    final permissions = channels.arguments('requestPermissions');
    expect(permissions['alert'], isTrue);
    expect(permissions['badge'], isTrue);
    expect(permissions['sound'], isTrue);
    expect(permissions['provisional'], isFalse);
    expect(permissions['critical'], isFalse);
  });
}

Future<void> _show(
  SystemMessageNotifier notifier, {
  bool group = false,
  bool reply = true,
  bool sound = true,
  bool vibration = true,
  bool alert = true,
  String soundID = MessageNotificationSoundIds.defaultId,
  String? avatarPath,
  DateTime? timestamp,
  bool Function()? isCurrent,
  String? senderID,
  int? groupMemberCount,
}) =>
    notifier.show(
      id: 42,
      target: _target(group: group),
      presentation: _presentation(group: group, reply: reply, soundID: soundID),
      sound: sound,
      vibration: vibration,
      alert: alert,
      avatarPath: avatarPath,
      timestamp: timestamp,
      isCurrent: isCurrent,
      senderID: senderID,
      groupMemberCount: groupMemberCount,
    );

class _Channels {
  _Channels(this.binding) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_plugin,
        (call) async {
      pluginCalls.add(call);
      if (call.method == 'initialize') return true;
      if (call.method == 'getNotificationAppLaunchDetails') {
        return launchDetails;
      }
      return null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_bridge,
        (call) async {
      bridgeCalls.add(call);
      return bridgeReply == null ? true : await bridgeReply!(call);
    });
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',
        (data) async {
      final path = utf8.decode(
          data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      if (path != _logo) {
        throw StateError('Unexpected notification asset: $path');
      }
      assetReads++;
      return assetReply == null
          ? ByteData.sublistView(_png)
          : await assetReply!();
    });
  }

  final TestWidgetsFlutterBinding binding;
  final pluginCalls = <MethodCall>[];
  final bridgeCalls = <MethodCall>[];
  Map<String, Object?>? launchDetails;
  Future<Object?> Function(MethodCall)? bridgeReply;
  Future<ByteData?> Function()? assetReply;
  int assetReads = 0;

  SystemMessageNotifier use(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    if (platform == TargetPlatform.android) {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
    } else {
      IOSFlutterLocalNotificationsPlugin.registerWith();
    }
    return SystemMessageNotifier(FlutterLocalNotificationsPlugin(),
        platform: platform);
  }

  Map<Object?, Object?> arguments(String method) =>
      _map(pluginCalls.lastWhere((c) => c.method == method).arguments);
  Map<Object?, Object?> bridgeArguments(String method) =>
      _map(bridgeCalls.lastWhere((c) => c.method == method).arguments);

  void dispose() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_plugin, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_bridge, null);
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  }
}
