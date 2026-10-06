import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/live/group_live_module.dart';
import 'package:openim/pages/group_features/live/pages/live_manage_page.dart';
import 'package:openim/pages/group_features/live/pages/live_push_page.dart';
import 'package:openim/pages/group_features/live/pages/live_room_page.dart';
import 'package:openim/pages/group_features/live/widgets/live_style.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'live_test_support.dart';

const _sdk = MethodChannel('flutter_openim_sdk');
const _open = ValueKey('open-live-entry');

class _Routes extends NavigatorObserver {
  int pushed = 0, popped = 0, replaced = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped++;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replaced++;
  }
}

class _Fixture {
  _Fixture({
    this.status,
    this.canConfigure = true,
    this.canManage = true,
    this.canPush = true,
    this.createdStatus = 'AUTHORIZED',
  }) {
    transport = LiveTransport((request) {
      if (request.path.endsWith('/feature-capabilities')) {
        return capabilityReply?.future ??
            {
              'groupID': 'group#1',
              'capabilityVersion': 1,
              'cacheTTLSeconds': 300,
              'live': {
                'canConfigure': canConfigure,
                'canManage': canManage,
                'canPush': canPush,
              }
            };
      }
      if (request.path.endsWith('/current')) {
        if (failCurrent) throw StateError('current unavailable');
        return currentReply?.future ?? currentDTO();
      }
      if (request.path.endsWith('/authorize')) {
        created = true;
        return {
          ...liveDTO(status: createdStatus),
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 1,
            'live': {
              'sessionID': 'live-1',
              'status': createdStatus == 'SCHEDULED' ? 'scheduled' : 'ready',
              'anchorUserID': 'anchor',
            },
            'games': {},
          }
        };
      }
      if (request.path.endsWith('/push-info')) {
        return {
          'rtmpServer': 'rtmp://push.example.test/live',
          'streamKey': 'fixture-only',
          'expiresAt': DateTime.utc(2035).toIso8601String(),
        };
      }
      return liveDTO(status: status ?? createdStatus);
    });
    store = GroupFeatureStore(
        api: transport.api(),
        sessionCurrent: () => sessionCurrent,
        fetchGroups: (_) async => []);
  }
  final String? status;
  final String createdStatus;
  final bool canConfigure, canManage, canPush;
  late final LiveTransport transport;
  late final GroupFeatureStore store;
  final dark = ValueNotifier(false);
  final routes = _Routes();
  bool sessionCurrent = true,
      failCurrent = false,
      returned = false,
      created = false;
  Completer<Map<String, dynamic>>? currentReply, capabilityReply;
  Completer<void>? permissionCalibration;
  Map<String, dynamic>? currentValue;
  int count(String suffix) => transport.requests
      .where((request) => request.path.endsWith(suffix))
      .length;
  Map<String, dynamic> currentDTO() =>
      currentValue ??
      {
        'active': status != null || created,
        if (status != null || created)
          'session': liveDTO(status: status ?? createdStatus),
      };
  GroupFeatureContext _cachedContext() => store.context(
      id: 'group#1',
      name: '直播群',
      userID: 'self',
      admin: canManage,
      current: () => sessionCurrent);
  GroupFeatureContext entryContext() {
    final cached = _cachedContext();
    final wait = permissionCalibration;
    if (wait == null) return cached;
    return GroupFeatureContext(
        groupID: cached.groupID,
        groupName: cached.groupName,
        currentUserID: cached.currentUserID,
        api: cached.api,
        features: cached.features,
        capabilities: cached.capabilities,
        sessionCurrent: cached.sessionCurrent,
        capabilitiesCurrent: cached.capabilitiesCurrent,
        onFeaturesChanged: cached.onFeaturesChanged,
        events: cached.events,
        readContext: _cachedContext,
        reloadCapabilities: (_) async {
          await wait.future;
          return _cachedContext();
        });
  }

  void dispose() {
    store.dispose();
    dark.dispose();
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await EasyLoading.dismiss(animation: false);
  await tester.pump();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> _mount(WidgetTester tester, _Fixture fixture,
    {bool warmPermissions = true}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (warmPermissions) {
    await tester.runAsync(() => fixture.store.loadCapabilities('group#1'));
  }
  configureEasyLoadingInteractions();
  addTearDown(() async {
    // Dismiss while the EasyLoading overlay is still mounted, then dispose the
    // route. Do not await its future across the widget-test fake-async boundary.
    await _unmount(tester);
  });
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => ValueListenableBuilder<bool>(
          valueListenable: fixture.dark,
          builder: (_, dark, __) => GetMaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light),
              translations: TranslationService(),
              locale: const Locale('zh', 'CN'),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('zh', 'CN')],
              navigatorObservers: [fixture.routes],
              builder: EasyLoading.init(),
              home: Scaffold(body: Builder(builder: (context) {
                return Center(
                    child: ElevatedButton(
                        key: _open,
                        onPressed: () {
                          fixture.returned = false;
                          unawaited(GroupLiveModule.openManage(context,
                                  featureContext: fixture.entryContext())
                              .then<void>((_) {
                            fixture.returned = true;
                          }));
                        },
                        child: const Text('直播管理入口')));
              }))))));
  await _frames(tester);
}

Future<void> _openEntry(WidgetTester tester) async {
  await tester.tap(find.byKey(_open));
  await _frames(tester);
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(LiveBackButton).hitTestable());
  await _frames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, (call) async {
      if (call.method == 'getGroupMembersInfo' ||
          call.method == 'getGroupMemberList') {
        return jsonEncode([
          {
            'groupID': 'group#1',
            'userID': 'anchor',
            'nickname': '主播A',
            'roleLevel': 20
          }
        ]);
      }
      return null;
    });
  });
  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, null);
  });

  for (final status in ['SCHEDULED', 'AUTHORIZED', 'LIVE']) {
    testWidgets('public management entry resumes $status on its original route',
        (tester) async {
      final fixture = _Fixture(status: status);
      addTearDown(fixture.dispose);
      await _mount(tester, fixture);
      await _openEntry(tester);
      expect(find.byType(LivePushPage), findsOneWidget);
      expect(find.byType(LiveManagePage, skipOffstage: false), findsNothing);
      expect(fixture.count('/current'), 1);
      expect(fixture.count('/feature-capabilities'), 1);
      expect(fixture.count('/push-info'), status == 'SCHEDULED' ? 0 : 1);
      expect(fixture.returned, isFalse);
      expect(fixture.routes.pushed, 2); // Home plus one entry route.
      expect(fixture.routes.replaced, 0);
      for (var rebuild = 0; rebuild < 3; rebuild++) {
        fixture.dark.value = !fixture.dark.value;
        await _frames(tester);
      }
      expect(fixture.count('/current'), 1);
      expect(fixture.count('/feature-capabilities'), 1);
      await _back(tester);
      expect(fixture.returned, isTrue);
      expect(find.byKey(_open).hitTestable(), findsOneWidget);
      expect(find.byType(LivePushPage, skipOffstage: false), findsNothing);
      expect(find.byType(LiveManagePage, skipOffstage: false), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no active session opens creation after a single current read',
      (tester) async {
    final fixture = _Fixture(canPush: false);
    addTearDown(fixture.dispose);
    await _mount(tester, fixture);
    await _openEntry(tester);
    expect(find.byType(LiveManagePage), findsOneWidget);
    expect(find.byType(LivePushPage, skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('live-room-name')), findsOneWidget);
    expect(find.text('开启直播'), findsOneWidget);
    expect(fixture.count('/current'), 1);
    expect(fixture.count('/push-info'), 0);
    fixture.dark.value = true;
    await _frames(tester);
    expect(fixture.count('/current'), 1);
    expect(fixture.count('/feature-capabilities'), 1);
    expect(fixture.returned, isFalse);
    await _back(tester);
    expect(fixture.returned, isTrue);
    expect(find.byType(LiveManagePage, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a manager without push permission never requests private keys',
      (tester) async {
    final fixture = _Fixture(status: 'LIVE', canPush: false);
    addTearDown(fixture.dispose);
    await _mount(tester, fixture);
    await _openEntry(tester);
    expect(find.byType(LivePushPage), findsOneWidget);
    expect(find.text('结束直播'), findsOneWidget);
    expect(
        find.text('rtmp://push.example.test/live/fixture-only'), findsNothing);
    expect(fixture.count('/push-info'), 0);
    expect(fixture.count('/current'), 1);
    await _back(tester);
    expect(fixture.returned, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final scheduled in [false, true]) {
    testWidgets(
        '${scheduled ? 'scheduled' : 'immediate'} creation through public entry returns home when push is closed',
        (tester) async {
      final fixture =
          _Fixture(createdStatus: scheduled ? 'SCHEDULED' : 'AUTHORIZED');
      addTearDown(fixture.dispose);
      await _mount(tester, fixture);
      await _openEntry(tester);
      final name = find.byKey(const ValueKey('live-room-name'));
      await tester.ensureVisible(name);
      await tester.enterText(name, '群直播间');
      await tester.ensureVisible(find.text('请选择主播'));
      await tester.tap(find.text('请选择主播'));
      await _frames(tester);
      await tester.tap(find.text('主播A'));
      await _frames(tester);
      if (scheduled) {
        await tester.ensureVisible(find.text('预约开播'));
        await tester.tap(find.text('预约开播'));
        await _frames(tester);
        await tester.tap(find.text('完成'));
        await _frames(tester);
      }
      await tester.ensureVisible(find.text('开启直播'));
      await tester.tap(find.text('开启直播'));
      await _frames(tester);
      expect(find.byType(LivePushPage), findsOneWidget);
      expect(fixture.count('/authorize'), 1);
      expect(fixture.count('/current'), 1);
      expect(fixture.count('/push-info'), scheduled ? 0 : 1);
      if (scheduled) {
        expect(find.text('直播已预约'), findsOneWidget);
        final write = fixture.transport.requests
            .singleWhere((request) => request.path.endsWith('/authorize'));
        expect((write.data as Map)['scheduledStartAt'], isNotNull);
      }
      expect(fixture.returned, isFalse);
      await _back(tester);
      expect(fixture.returned, isTrue);
      expect(find.byKey(_open).hitTestable(), findsOneWidget);
      expect(find.byType(LiveManagePage, skipOffstage: false), findsNothing);
      expect(find.byType(LivePushPage, skipOffstage: false), findsNothing);
      expect(fixture.count('/authorize'), 1);
      await _unmount(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an anchor can push without manager revoke or end controls',
      (tester) async {
    final fixture =
        _Fixture(status: 'AUTHORIZED', canConfigure: false, canManage: false);
    addTearDown(fixture.dispose);
    await _mount(tester, fixture);
    await _openEntry(tester);
    expect(find.byType(LivePushPage), findsOneWidget);
    expect(find.text('rtmp://push.example.test/live/fixture-only'),
        findsOneWidget);
    expect(find.text('撤销直播'), findsNothing);
    expect(find.text('结束直播'), findsNothing);
    expect(fixture.count('/push-info'), 1);
    expect(fixture.count('/current'), 1);
    await _back(tester);
    expect(fixture.returned, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current read failure stays retryable and never shows creation',
      (tester) async {
    final fixture = _Fixture()..failCurrent = true;
    addTearDown(fixture.dispose);
    await _mount(tester, fixture);
    await _openEntry(tester);
    expect(find.byType(LiveManagePage, skipOffstage: false), findsNothing);
    expect(find.byType(LivePushPage, skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('live-room-name')), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    expect(fixture.returned, isFalse);
    fixture.failCurrent = false;
    await tester.tap(find.text('重试'));
    await _frames(tester);
    expect(find.byType(LiveManagePage), findsOneWidget);
    expect(fixture.count('/current'), 2);
    expect(fixture.count('/feature-capabilities'), 1);
    await _back(tester);
    expect(fixture.returned, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary member permission resolves to watching without keys',
      (tester) async {
    final fixture = _Fixture(
        status: 'SCHEDULED',
        canConfigure: false,
        canManage: false,
        canPush: false);
    addTearDown(fixture.dispose);
    await _mount(tester, fixture);
    await _openEntry(tester);
    expect(find.byType(LiveRoomPage), findsOneWidget);
    expect(find.byType(LivePushPage, skipOffstage: false), findsNothing);
    expect(find.byType(LiveManagePage, skipOffstage: false), findsNothing);
    expect(fixture.count('/current'), 1);
    expect(fixture.count('/push-info'), 0);
    expect(fixture.count('/play-info'), 0);
    expect(fixture.returned, isFalse);
    await _back(tester);
    expect(fixture.returned, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final closeRoute in [true, false]) {
    testWidgets(
        'late current response after ${closeRoute ? 'exit' : 'account invalidation'} cannot open a child page',
        (tester) async {
      final fixture = _Fixture(status: 'AUTHORIZED');
      addTearDown(fixture.dispose);
      final reply = Completer<Map<String, dynamic>>();
      fixture.currentReply = reply;
      await _mount(tester, fixture);
      await _openEntry(tester);
      expect(fixture.count('/current'), 1);
      expect(find.byType(LivePushPage), findsNothing);
      if (closeRoute) {
        await _back(tester);
        expect(fixture.returned, isTrue);
      } else {
        fixture.sessionCurrent = false;
      }
      reply.complete(fixture.currentDTO());
      await _frames(tester);
      expect(find.byType(LivePushPage, skipOffstage: false), findsNothing);
      expect(find.byType(LiveManagePage, skipOffstage: false), findsNothing);
      expect(fixture.count('/push-info'), 0);
      expect(fixture.routes.replaced, 0);
      if (!closeRoute) await _back(tester);
      expect(find.byKey(_open).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late permission calibration after exit cannot open creation',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final reply = Completer<Map<String, dynamic>>();
    fixture.capabilityReply = reply;
    await _mount(tester, fixture, warmPermissions: false);
    await _openEntry(tester);
    expect(fixture.count('/feature-capabilities'), 1);
    await _back(tester);
    expect(fixture.returned, isTrue);
    reply.complete({
      'groupID': 'group#1',
      'capabilityVersion': 1,
      'cacheTTLSeconds': 300,
      'live': {'canConfigure': true}
    });
    await _frames(tester);
    expect(find.byType(LiveManagePage, skipOffstage: false), findsNothing);
    expect(find.byType(LivePushPage, skipOffstage: false), findsNothing);
    expect(fixture.count('/push-info'), 0);
    expect(find.byKey(_open).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final reconciled in [true, false]) {
    testWidgets(
        'new SDK scene during permission wait ${reconciled ? 'reconciles once' : 'remains retryable on conflict'}',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final wait = fixture.permissionCalibration = Completer<void>();
      await _mount(tester, fixture);
      await _openEntry(tester);
      expect(fixture.count('/current'), 1);
      expect(find.byType(LiveManagePage), findsNothing);
      fixture.store.seed(GroupInfo(
          groupID: 'group#1',
          ex: jsonEncode({
            'groupFeatures': {
              'schemaVersion': 1,
              'revision': 2,
              'live': {
                'sessionID': 'live-1',
                'status': 'ready',
                'anchorUserID': 'anchor'
              },
              'games': {},
            }
          })));
      if (reconciled) {
        fixture.currentValue = {'active': true, 'session': liveDTO()};
      }
      await _frames(tester); // The store recalibrates its invalidated cache.
      wait.complete();
      await _frames(tester);
      expect(fixture.count('/current'), 2);
      expect(find.byType(LiveManagePage, skipOffstage: false), findsNothing);
      if (reconciled) {
        expect(find.byType(LivePushPage), findsOneWidget);
        expect(fixture.count('/push-info'), 1);
      } else {
        expect(find.byType(LivePushPage), findsNothing);
        expect(find.text('重试'), findsOneWidget);
        expect(find.text('直播场次信息正在更新，请重试'), findsOneWidget);
        expect(fixture.count('/push-info'), 0);
        fixture.dark.value = true;
        await _frames(tester);
        expect(fixture.count('/current'), 2);
      }
      expect(fixture.returned, isFalse);
      await _back(tester);
      expect(fixture.returned, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
