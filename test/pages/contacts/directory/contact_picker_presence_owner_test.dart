import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/presence/contact_presence_policy.dart';
import 'package:openim/pages/contacts/presence_store.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _sdkChannel = MethodChannel('flutter_openim_sdk');

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends GetxController implements HomeLogic {
  @override
  final unhandledFriendApplicationCount = 0.obs;
  @override
  final unhandledGroupApplicationCount = 0.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StatusSdk {
  final subscribed = <String>{};
  final subscriptions = <Set<String>>[];
  final unsubscriptions = <Set<String>>[];
  Completer<void>? subscriptionGate;
  Completer<void>? unsubscriptionGate;

  Future<Object?> handle(MethodCall call) async {
    final ids = Set<String>.from((call.arguments as Map)['userIDs'] as List);
    switch (call.method) {
      case 'subscribeUsersStatus':
        subscriptions.add(ids);
        subscribed.addAll(ids);
        await subscriptionGate?.future;
        return '[]';
      case 'unsubscribeUsersStatus':
        unsubscriptions.add(ids);
        subscribed.removeAll(ids);
        await unsubscriptionGate?.future;
        return null;
      default:
        throw StateError('Unexpected SDK method: ${call.method}');
    }
  }
}

class _PresenceHttp implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final records = <String, Map<String, dynamic>>{};
  Completer<void>? responseGate;
  int nextPresenceErrorCode = 0;

  @override
  void close({bool force = false}) {
    final gate = responseGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    final presence = options.path.endsWith('/chat/users/presence');
    if (presence) requests.add(options);
    final errorCode = presence ? nextPresenceErrorCode : 0;
    if (presence) nextPresenceErrorCode = 0;
    final users = presence
        ? [
            for (final id in options.data['userIDs'] as List)
              {
                'userID': id,
                'online': false,
                'showLastSeen': true,
                ...?records[id],
              },
          ]
        : null;
    if (presence) await responseGate?.future;
    return ResponseBody.fromString(
      jsonEncode({
        'errCode': errorCode,
        'data': presence ? {'users': users} : {'stars': [], 'syncAt': 0},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Future<void> _credentials(String token) async {
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': 'self',
    'chatToken': token,
    'imToken': 'same-im-token',
  }));
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _flushPresence(WidgetTester tester, ContactsLogic logic) async {
  await tester.pump(const Duration(milliseconds: 120));
  final pending = logic.refreshPresence(force: false);
  await _drain(tester);
  await pending;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _StatusSdk sdk;
  late _PresenceHttp presenceHttp;
  late Dio previousHttp;

  setUp(() async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    // No login certificate: presence HTTP cannot run in these SDK tests.
    expect(DataSp.chatToken, isNull);
    Get.put<AppController>(_App());
    Get.put<IMController>(_IM());
    Get.put<HomeLogic>(_Home());
    previousHttp = http.dio;
    presenceHttp = _PresenceHttp();
    http.dio = Dio()..httpClientAdapter = presenceHttp;
    sdk = _StatusSdk();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdkChannel, sdk.handle);
  });

  tearDown(() async {
    Get.reset();
    http.dio.close(force: true);
    http.dio = previousHttp;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdkChannel, null);
  });

  ContactsLogic createLogic() {
    // Exercise the real subscription owner logic without SDK directory loading.
    final logic = ContactsLogic(fetchFriendsPage: (_, __) async => []);
    addTearDown(logic.onDelete.call);
    return logic;
  }

  testWidgets('same-peer profile owners reuse presence and preserve its cache',
      (tester) async {
    await _credentials('chat');
    final logic = createLogic();
    final first = Object();
    final second = Object();
    logic.setProfilePresence(first, 'A');
    await _flushPresence(tester, logic);
    final cached = logic.presence.users['A'];
    expect(cached, isNotNull);
    expect(sdk.subscriptions, [
      {'A'}
    ]);
    expect(presenceHttp.requests, hasLength(1));

    logic.setProfilePresence(first, 'A');
    logic.setProfilePresence(second, 'A');
    logic.setProfilePresence(Object(), null);
    await _flushPresence(tester, logic);
    expect(sdk.subscriptions, hasLength(1));
    expect(presenceHttp.requests, hasLength(1));
    logic.setProfilePresence(first, null);
    logic.setProfilePresence(first, null);
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, {'A'});
    expect(sdk.unsubscriptions, isEmpty);
    expect(presenceHttp.requests, hasLength(1));

    logic.setProfilePresence(second, null);
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, isEmpty);
    expect(sdk.unsubscriptions, [
      {'A'}
    ]);
    expect(logic.presence.users['A'], same(cached),
        reason: 'Returning from a chat keeps the last authoritative snapshot.');
    expect(presenceHttp.requests, hasLength(1));
    logic.onDelete();
    await tester.pump();
  });

  testWidgets('a new profile retries missing presence without resubscribing',
      (tester) async {
    await _credentials('chat');
    presenceHttp.nextPresenceErrorCode = 500;
    final logic = createLogic();
    final first = Object();
    final second = Object();
    logic.setProfilePresence(first, 'A');
    await _drain(tester);
    expect(presenceHttp.requests, hasLength(1));
    expect(logic.presence.users['A'], isNull,
        reason: 'A failed initial query leaves no authoritative snapshot.');
    expect(sdk.subscriptions, [
      {'A'}
    ]);

    final lastSeen = DateTime.now()
        .subtract(const Duration(hours: 2))
        .millisecondsSinceEpoch;
    presenceHttp.records['A'] = {'online': false, 'lastSeenAt': lastSeen};
    logic.setProfilePresence(second, 'A');
    await _drain(tester);
    expect(presenceHttp.requests, hasLength(2));
    expect(sdk.subscriptions, hasLength(1),
        reason: 'Only the missing API snapshot needs another request.');
    expect(logic.presence.users['A']!.online, isFalse);
    expect(logic.presence.users['A']!.lastSeenAt, lastSeen);

    logic.setProfilePresence(second, 'A');
    logic.setProfilePresence(Object(), 'A');
    await _drain(tester);
    expect(presenceHttp.requests, hasLength(2),
        reason:
            'Known shared peers retain the normal no-op registration path.');
    expect(sdk.subscriptions, hasLength(1));
    logic.onDelete();
    await tester.pump();
  });

  testWidgets('SDK signals wait for authoritative status and last-seen time',
      (tester) async {
    await _credentials('chat');
    final oldSeen = DateTime.now()
        .subtract(const Duration(hours: 2))
        .millisecondsSinceEpoch;
    final confirmedSeen = DateTime.now()
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    presenceHttp.records['A'] = {'online': false, 'lastSeenAt': oldSeen};
    final logic = createLogic()..onInit();
    logic.setProfilePresence(Object(), 'A');
    await _flushPresence(tester, logic);
    final first = logic.presence.users['A']!;
    final published = <UserPresence>[];
    final changes = logic.presence.users.listen((users) {
      final current = users['A'];
      if (current != null) published.add(current);
    });
    addTearDown(changes.cancel);
    await tester.pump();
    published.clear();
    final im = Get.find<IMController>();

    Future<void> confirm(int sdkStatus, Map<String, dynamic> record,
        UserPresence previous) async {
      presenceHttp.records['A'] = record;
      final gate = presenceHttp.responseGate = Completer<void>();
      final before = presenceHttp.requests.length;
      im.userStatusChangedSubject
          .add(UserStatusInfo(userID: 'A', status: sdkStatus));
      await tester.pump();
      expect(logic.presence.users['A'], same(previous),
          reason: 'A SDK signal cannot publish an unconfirmed status.');
      await tester.pump(const Duration(milliseconds: 120));
      await _drain(tester);
      expect(presenceHttp.requests, hasLength(before + 1));
      expect(logic.presence.users['A'], same(previous));
      gate.complete();
      await _drain(tester);
      presenceHttp.responseGate = null;
    }

    // The original flicker: online SDK, followed by an older offline HTTP row.
    await confirm(1, {'online': false, 'lastSeenAt': oldSeen}, first);
    expect(logic.presence.users['A'], same(first));
    expect(published, isEmpty);
    await confirm(0, {'online': true, 'lastSeenAt': null}, first);
    final online = logic.presence.users['A']!;
    expect(online.online, isTrue);
    expect(online.lastSeenAt, isNull);
    await confirm(0, {'online': false, 'lastSeenAt': confirmedSeen}, online);
    final offline = logic.presence.users['A']!;
    expect(offline.online, isFalse);
    expect(offline.lastSeenAt, confirmedSeen,
        reason: 'Offline time comes from the API rather than callback time.');
    expect(offline.label, isNot('presenceJustNow'.tr));
    expect(published, hasLength(2),
        reason: 'Only confirmed online and offline changes are published.');
    await confirm(1, {'online': true}, offline);
    expect(logic.presence.users['A']!.online, isTrue);
    expect(published, hasLength(3));
    expect(sdk.subscriptions, hasLength(1),
        reason: 'Status signals refresh HTTP without subscribing again.');
    logic.onDelete();
    await tester.pump();
  });

  for (final secondEvent in [false, true]) {
    testWidgets(
        'a new SDK signal invalidates HTTP before the queued refresh ($secondEvent)',
        (tester) async {
      await _credentials('chat');
      final oldSeen = DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch;
      final confirmedSeen = DateTime.now()
          .subtract(const Duration(minutes: 5))
          .millisecondsSinceEpoch;
      presenceHttp.records['A'] = {'online': false, 'lastSeenAt': oldSeen};
      final logic = createLogic()..onInit();
      logic.setProfilePresence(Object(), 'A');
      await _flushPresence(tester, logic);
      final confirmed = logic.presence.users['A']!;
      final published = <UserPresence>[];
      final changes = logic.presence.users.listen((users) {
        final current = users['A'];
        if (current != null) published.add(current);
      });
      addTearDown(changes.cancel);
      await tester.pump();
      published.clear();

      // A is an earlier poll with a response that disagrees with the last
      // confirmation. Hold it beyond the SDK event that invalidates it.
      presenceHttp.records['A'] = {'online': true};
      final gateA = presenceHttp.responseGate = Completer<void>();
      final requestA = logic.presence.refresh(['A']);
      await _drain(tester);
      expect(presenceHttp.requests, hasLength(2));
      final im = Get.find<IMController>();
      im.userStatusChangedSubject.add(UserStatusInfo(userID: 'A', status: 0));
      await tester.pump();
      expect(logic.presence.users['A'], same(confirmed));
      presenceHttp.records['A'] = {
        'online': false,
        'lastSeenAt': confirmedSeen,
      };
      final gateB = presenceHttp.responseGate = Completer<void>();
      addTearDown(() {
        if (!gateA.isCompleted) gateA.complete();
        if (!gateB.isCompleted) gateB.complete();
      });

      if (!secondEvent) {
        gateA.complete();
        await _drain(tester);
        await requestA;
        expect(presenceHttp.requests, hasLength(2),
            reason: 'A returned before the 120ms confirmation query started.');
        expect(logic.presence.users['A'], same(confirmed));
        expect(published, isEmpty,
            reason: 'An accepted SDK signal invalidates A immediately.');
      }
      await tester.pump(const Duration(milliseconds: 120));
      await _drain(tester);
      expect(presenceHttp.requests, hasLength(3));
      expect(logic.presence.users['A'], same(confirmed));

      if (secondEvent) {
        // B has now started while A is still in flight. A newer event must
        // invalidate B as well, even if both finish before the next timer.
        im.userStatusChangedSubject.add(UserStatusInfo(userID: 'A', status: 1));
        await tester.pump();
        presenceHttp.records['A'] = {'online': true};
        presenceHttp.responseGate = null;
        gateA.complete();
        gateB.complete();
        await _drain(tester);
        await requestA;
        expect(presenceHttp.requests, hasLength(3));
        expect(logic.presence.users['A'], same(confirmed));
        expect(published, isEmpty);
        await tester.pump(const Duration(milliseconds: 120));
        await _drain(tester);
        expect(presenceHttp.requests, hasLength(4));
        expect(logic.presence.users['A']!.online, isTrue);
        expect(logic.presence.users['A']!.lastSeenAt, isNull);
      } else {
        gateB.complete();
        await _drain(tester);
        expect(logic.presence.users['A']!.online, isFalse);
        expect(logic.presence.users['A']!.lastSeenAt, confirmedSeen);
      }
      expect(published, hasLength(1),
          reason: 'Only the latest authoritative confirmation is published.');
      expect(sdk.subscriptions, hasLength(1));
      logic.onDelete();
      await tester.pump();
    });
  }

  testWidgets('SDK batches preserve privacy and ignore hidden or unknown users',
      (tester) async {
    await _credentials('chat');
    final lastSeen =
        DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch;
    presenceHttp.records['hidden'] = {
      'online': false,
      'showLastSeen': false,
      'lastSeenAt': lastSeen,
    };
    final logic = createLogic()..onInit();
    logic.setDirectoryPresenceVisible(
        Object(), {'A', 'B', 'hidden', 'assistant'});
    await _flushPresence(tester, logic);
    final im = Get.find<IMController>();
    final hidden = logic.presence.users['hidden']!;
    final requestCount = presenceHttp.requests.length;
    for (final event in [
      UserStatusInfo(userID: 'hidden', status: 1),
      UserStatusInfo(userID: 'hidden', status: 0),
      UserStatusInfo(userID: 'not-watched', status: 1),
      UserStatusInfo(userID: 'A', status: 2),
    ]) {
      im.userStatusChangedSubject.add(event);
    }
    await tester.pump(const Duration(milliseconds: 200));
    await _drain(tester);
    expect(presenceHttp.requests, hasLength(requestCount));
    expect(logic.presence.users['hidden'], same(hidden));
    expect(hidden.hidden, isTrue);
    expect(hidden.displayOnline, isFalse);
    expect(
        ContactPresencePolicy.resolve(
                userID: 'assistant',
                presence: logic.presence.users['assistant'])!
            .displayOnline,
        isTrue);

    presenceHttp.records['A'] = {'online': true};
    presenceHttp.records['B'] = {'online': false, 'lastSeenAt': lastSeen};
    for (final event in [
      UserStatusInfo(userID: 'A', status: 0),
      UserStatusInfo(userID: 'A', status: 1),
      UserStatusInfo(userID: 'B', status: 1),
      UserStatusInfo(userID: 'B', status: 0),
      UserStatusInfo(userID: 'A', status: 0),
    ]) {
      im.userStatusChangedSubject.add(event);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 119));
    expect(presenceHttp.requests, hasLength(requestCount));
    await tester.pump(const Duration(milliseconds: 1));
    await _drain(tester);
    expect(presenceHttp.requests, hasLength(requestCount + 1));
    expect((presenceHttp.requests.last.data['userIDs'] as List).toSet(),
        {'A', 'B'});
    expect(logic.presence.users['A']!.online, isTrue);
    expect(logic.presence.users['B']!.lastSeenAt, lastSeen);
    expect(sdk.subscriptions, hasLength(1));

    // A privacy change from the authority applies before later SDK signals.
    presenceHttp.records['A'] = {
      'online': true,
      'showLastSeen': false,
      'lastSeenAt': lastSeen,
    };
    im.userStatusChangedSubject.add(UserStatusInfo(userID: 'A', status: 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await _drain(tester);
    final private = logic.presence.users['A']!;
    expect(private.hidden, isTrue);
    expect(private.displayOnline, isFalse);
    expect(private.lastSeenAt, lastSeen);
    final afterPrivacy = presenceHttp.requests.length;
    im.userStatusChangedSubject.add(UserStatusInfo(userID: 'A', status: 1));
    await tester.pump(const Duration(milliseconds: 200));
    await _drain(tester);
    expect(presenceHttp.requests, hasLength(afterPrivacy));
    expect(logic.presence.users['A'], same(private));
    logic.onDelete();
    await tester.pump();
  });

  testWidgets(
      'background pauses SDK batches even behind a gated normal refresh',
      (tester) async {
    await _credentials('chat');
    final oldSeen = DateTime.now()
        .subtract(const Duration(hours: 2))
        .millisecondsSinceEpoch;
    presenceHttp.records['A'] = {'online': false, 'lastSeenAt': oldSeen};
    final logic = createLogic()..onInit();
    logic.setProfilePresence(Object(), 'A');
    await _flushPresence(tester, logic);
    final confirmed = logic.presence.users['A']!;

    presenceHttp.records['A'] = {'online': true};
    final gate = presenceHttp.responseGate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final blockedRefresh = logic.refreshPresence();
    await _drain(tester);
    expect(presenceHttp.requests, hasLength(2));
    final im = Get.find<IMController>();
    im.userStatusChangedSubject.add(UserStatusInfo(userID: 'A', status: 0));
    await tester.pump();
    logic.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 120));
    await _drain(tester);
    expect(presenceHttp.requests, hasLength(2),
        reason:
            'The pending SDK batch cannot bypass paused subscription work.');
    expect(logic.presence.users['A'], same(confirmed));

    im.userStatusChangedSubject.add(UserStatusInfo(userID: 'A', status: 1));
    im.userStatusChangedSubject.add(UserStatusInfo(userID: 'A', status: 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _drain(tester);
    expect(presenceHttp.requests, hasLength(2));
    expect(logic.presence.users['A'], same(confirmed));

    gate.complete();
    await _drain(tester);
    await blockedRefresh;
    final pausedWork = logic.refreshPresence(force: false);
    await _drain(tester);
    await pausedWork;
    expect(sdk.subscribed, isEmpty);
    expect(logic.presence.users['A'], same(confirmed),
        reason: 'The invalidated earlier response cannot flash while paused.');
    expect(presenceHttp.requests, hasLength(2));

    presenceHttp.responseGate = null;
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, {'A'});
    expect(presenceHttp.requests, hasLength(3));
    expect(logic.presence.users['A']!.online, isTrue);
    expect(logic.presence.users['A']!.lastSeenAt, isNull);
    logic.onDelete();
    await tester.pump();
  });

  testWidgets(
      'a late presence HTTP result cannot cross a same-user token change',
      (tester) async {
    await _credentials('old-chat');
    final logic = createLogic()..onInit();
    logic.setProfilePresence(Object(), 'A');
    await _flushPresence(tester, logic);
    final cached = logic.presence.users['A'];
    presenceHttp.records['A'] = {'online': true};
    final gate = presenceHttp.responseGate = Completer<void>();
    Get.find<IMController>()
        .userStatusChangedSubject
        .add(UserStatusInfo(userID: 'A', status: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await _drain(tester);
    expect(presenceHttp.requests, hasLength(2));
    expect(presenceHttp.requests.last.headers['token'], 'old-chat');
    await _credentials('new-chat');
    gate.complete();
    await _drain(tester);
    expect(logic.presence.users['A'], same(cached));
    expect(logic.isCurrentSession, isFalse);
    logic.onDelete();
    await tester.pump();
  });

  testWidgets('pausing and releasing a picker preserves the main shared friend',
      (tester) async {
    final logic = createLogic();
    final picker = Object();
    logic.setPresenceVisible('A', true);
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, {'A'});

    logic.setDirectoryPresenceVisible(picker, {'A', 'B'});
    await tester.pump(const Duration(milliseconds: 119));
    expect(sdk.subscriptions, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    await logic.refreshPresence(force: false);
    expect(sdk.subscribed, {'A', 'B'});
    expect(sdk.subscriptions.last, {'B'});
    expect(sdk.unsubscriptions, isEmpty);

    logic.setDirectoryPresenceVisible(picker, {});
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, isEmpty);
    expect(sdk.unsubscriptions.single, {'A', 'B'});

    logic.setDirectoryPresenceVisible(picker, null);
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, {'A'});
    expect(sdk.subscriptions.last, {'A'});
    logic.onDelete();
    await tester.pump();
  });

  testWidgets('a profile detail overrides picker visibility until released',
      (tester) async {
    final logic = createLogic();
    final picker = Object();
    final detail = Object();
    logic.setDirectoryPresenceVisible(picker, {'A', 'B'});
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, {'A', 'B'});

    logic.setProfilePresence(detail, 'detail');
    await logic.refreshPresence(force: false);
    expect(sdk.subscribed, {'detail'});
    expect(sdk.unsubscriptions.last, {'A', 'B'});
    expect(sdk.subscriptions.last, {'detail'});

    // Scrolling the covered picker must not replace the profile subscription.
    logic.setDirectoryPresenceVisible(picker, {'B', 'C'});
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, {'detail'});
    expect(sdk.subscriptions, hasLength(2));

    logic.setProfilePresence(detail, null);
    await logic.refreshPresence(force: false);
    expect(sdk.subscribed, {'B', 'C'});
    expect(sdk.unsubscriptions.last, {'detail'});
    expect(sdk.subscriptions.last, {'B', 'C'});
    logic.onDelete();
    await tester.pump();
  });

  testWidgets('each picker releases only itself and closing cancels new work',
      (tester) async {
    final logic = createLogic();
    final first = Object();
    final second = Object();
    logic.setPresenceVisible('main', true);
    await _flushPresence(tester, logic);
    logic.setDirectoryPresenceVisible(first, {'A', 'B'});
    await _flushPresence(tester, logic);
    logic.setDirectoryPresenceVisible(second, {'C'});
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, {'C'});

    logic.setDirectoryPresenceVisible(second, null);
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, {'A', 'B'});

    logic.setDirectoryPresenceVisible(second, {'C'});
    await _flushPresence(tester, logic);
    final subscriptionCount = sdk.subscriptions.length;
    final unsubscriptionCount = sdk.unsubscriptions.length;
    logic.setDirectoryPresenceVisible(first, null);
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, {'C'});
    expect(sdk.subscriptions, hasLength(subscriptionCount));
    expect(sdk.unsubscriptions, hasLength(unsubscriptionCount));

    logic.setDirectoryPresenceVisible(second, null);
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, {'main'});

    final subscriptionsBeforeClose = sdk.subscriptions.length;
    logic.setDirectoryPresenceVisible(first, {'pending'});
    logic.onDelete();
    logic.setDirectoryPresenceVisible(second, {'after-close'});
    await logic.refreshPresence();
    await tester.pump(const Duration(milliseconds: 500));
    expect(sdk.subscriptions, hasLength(subscriptionsBeforeClose));
    expect(sdk.subscribed, isEmpty);
  });

  testWidgets('replaced token permits pause and release without new work',
      (tester) async {
    await _credentials('old-chat');
    final logic = createLogic();
    final picker = Object();
    logic.setPresenceVisible('main', true);
    logic.setDirectoryPresenceVisible(picker, {'picker'});
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, {'picker'});
    expect(presenceHttp.requests.single.headers['token'], 'old-chat');
    final subscriptions = sdk.subscriptions.length;
    final requests = presenceHttp.requests.length;

    await _credentials('new-chat');
    expect(logic.isCurrentSession, isFalse);
    logic.setDirectoryPresenceVisible(picker, {});
    logic.setDirectoryPresenceVisible(Object(), {'rejected'});
    await logic.refreshPresence();
    await tester.pump(const Duration(milliseconds: 500));
    expect(sdk.subscriptions, hasLength(subscriptions));
    expect(sdk.unsubscriptions, isEmpty,
        reason: 'An old owner must not unsubscribe on the new SDK session.');
    expect(presenceHttp.requests, hasLength(requests));

    await _credentials('old-chat');
    await tester.pump(const Duration(milliseconds: 500));
    expect(sdk.subscriptions, hasLength(subscriptions));
    expect(sdk.unsubscriptions, isEmpty,
        reason: 'Inactive registration must not queue a later refresh.');
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, isEmpty,
        reason: 'The old picker owner remains registered with an empty batch.');

    logic.setDirectoryPresenceVisible(picker, {'picker'});
    await _flushPresence(tester, logic);
    await _credentials('new-chat');
    logic.setDirectoryPresenceVisible(picker, null);
    logic.setDirectoryPresenceVisible(Object(), {'rejected'});
    final removedBefore = sdk.unsubscriptions.length;
    await tester.pump(const Duration(milliseconds: 500));
    expect(sdk.unsubscriptions, hasLength(removedBefore));
    await _credentials('old-chat');
    await _flushPresence(tester, logic);
    expect(sdk.subscribed, {'main'},
        reason: 'Releasing a stale picker must restore only the main owner.');
    expect(
        presenceHttp.requests
            .every((request) => request.headers['token'] == 'old-chat'),
        isTrue);
    logic.onDelete();
    await tester.pump();
  });

  testWidgets('token replacement stops queued refresh after unsubscribe awaits',
      (tester) async {
    await _credentials('old-chat');
    final logic = createLogic();
    final picker = Object();
    logic.setDirectoryPresenceVisible(picker, {'A'});
    await _flushPresence(tester, logic);
    sdk.unsubscriptionGate = Completer<void>();
    logic.setDirectoryPresenceVisible(picker, {'B'});
    final pending = logic.refreshPresence(force: false);
    await _drain(tester);
    expect(sdk.unsubscriptions.single, {'A'});
    final queued = logic.refreshPresence();

    await _credentials('new-chat');
    sdk.unsubscriptionGate!.complete();
    await _drain(tester);
    await Future.wait([pending, queued]);
    await tester.pump(const Duration(milliseconds: 500));
    expect(sdk.subscriptions, [
      {'A'}
    ]);
    expect(sdk.unsubscriptions, [
      {'A'}
    ]);
    expect(presenceHttp.requests, hasLength(1));
    logic.onDelete();
    await tester.pump();
  });

  testWidgets('token replacement stops HTTP after subscribe awaits',
      (tester) async {
    await _credentials('old-chat');
    final logic = createLogic();
    sdk.subscriptionGate = Completer<void>();
    logic.setDirectoryPresenceVisible(Object(), {'A'});
    final pending = logic.refreshPresence(force: false);
    await _drain(tester);
    expect(sdk.subscriptions, [
      {'A'}
    ]);
    expect(presenceHttp.requests, isEmpty);

    await _credentials('new-chat');
    sdk.subscriptionGate!.complete();
    await _drain(tester);
    await pending;
    await tester.pump(const Duration(milliseconds: 500));
    expect(presenceHttp.requests, isEmpty);
    expect(sdk.subscriptions, [
      {'A'}
    ]);
    expect(sdk.unsubscriptions, isEmpty);
    logic.onDelete();
    await tester.pump();
  });

  testWidgets('old SDK status events cannot mutate presence or request HTTP',
      (tester) async {
    await _credentials('old-chat');
    final logic = createLogic()..onInit();
    logic.setDirectoryPresenceVisible(Object(), {'A'});
    await _flushPresence(tester, logic);
    final snapshot = logic.presence.users['A'];
    expect(snapshot, isNotNull);
    final requests = presenceHttp.requests.length;
    await _credentials('new-chat');
    final im = Get.find<IMController>();
    im.userStatusChangedSubject.add(UserStatusInfo(userID: 'A', status: 1));
    await _drain(tester);
    expect(logic.presence.users['A'], same(snapshot));
    im.userStatusChangedSubject.add(UserStatusInfo(userID: 'A', status: 0));
    await _drain(tester);
    expect(logic.presence.users['A'], same(snapshot));
    expect(presenceHttp.requests, hasLength(requests));
    expect(sdk.subscriptions, [
      {'A'}
    ]);
    expect(sdk.unsubscriptions, isEmpty);
    logic.onDelete();
    await tester.pump();
  });
}
