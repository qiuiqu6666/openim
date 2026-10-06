import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/pages/live_manage_page.dart';
import 'package:openim/pages/group_features/live/pages/live_push_page.dart';
import 'package:openim/pages/group_features/live/widgets/live_style.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_test_support.dart';

const _sdk = MethodChannel('flutter_openim_sdk');

/// Captured snapshots have real epoch guards; refreshing cannot resurrect them.
class _PermissionFixture {
  _PermissionFixture(this.api, {bool canPush = false}) : push = canPush;
  final GroupFeatureApi api;
  final events = StreamController<Map<String, dynamic>>.broadcast();
  bool active = true, push, configure = true, manage = true, tip = true;
  int epoch = 0, version = 1, refreshes = 0;
  GroupFeatures features = const GroupFeatures();

  GroupFeatureContext get snapshot => _makeSnapshot();

  GroupFeatureContext _makeSnapshot() {
    final capturedEpoch = epoch;
    return GroupFeatureContext(
        groupID: 'group#1',
        groupName: '直播群',
        currentUserID: 'self',
        api: api,
        features: features,
        capabilities: GroupFeatureCapabilities(
            version: version,
            live: GroupLiveCapabilities(
                canConfigure: configure,
                canManage: manage,
                canPush: push,
                canTip: tip,
                raw: const {
                  'tipCurrencies': [
                    {'code': 'USDT', 'label': 'USDT', 'decimals': 6}
                  ]
                })),
        sessionCurrent: () => active,
        capabilitiesCurrent: () => active && capturedEpoch == epoch,
        onFeaturesChanged: acceptSummary,
        reloadCapabilities: (force) async {
          refreshes++;
          return _makeSnapshot();
        },
        readContext: _makeSnapshot,
        onCapabilitiesInvalidated: () => change(push: false),
        events: events.stream);
  }

  void change({required bool push}) {
    this.push = push;
    epoch++;
    version++;
    events.add(
        {'key': 'groupFeatureCapabilitiesInvalidated', 'groupID': 'group#1'});
    events
        .add({'key': 'groupFeatureCapabilitiesResolved', 'groupID': 'group#1'});
  }

  void acceptSummary(Map<String, dynamic> raw) {
    final next = GroupFeatures.fromJson(raw);
    if (!next.valid || next.revision <= features.revision) return;
    features = next;
    change(push: next.live.isActive);
    events.add({
      'key': 'groupFeaturesChanged',
      'groupID': 'group#1',
      'data': {'groupFeatures': next.raw}
    });
  }
}

Map<String, dynamic> _summary({String status = 'ready', int revision = 1}) => {
      'schemaVersion': 1,
      'revision': revision,
      'live': {
        'sessionID': 'live-1',
        'status': status,
        'anchorUserID': 'anchor'
      },
      'games': {
        'sangong': {'enabled': false},
        'markSix': {'enabled': false}
      }
    };

Map<String, dynamic> _push(String key) => {
      'rtmpServer': 'rtmp://push.example.test/live',
      'streamKey': key,
      'expiresAt':
          DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String()
    };

Future<void> _mount(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  configureEasyLoadingInteractions();
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          supportedLocales: const [Locale('zh', 'CN')],
          builder: EasyLoading.init(),
          home: page)));
  await tester.pump();
  addTearDown(() => _unmount(tester));
}

Future<void> _unmount(WidgetTester tester) async {
  // Clear the overlay and its dismissal timer while its state is still mounted.
  await EasyLoading.dismiss(animation: false);
  await tester.pump();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _prepareCreate(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final name = find.byKey(const ValueKey('live-room-name'));
  await tester.ensureVisible(name);
  await tester.enterText(name, '群直播间');
  await tester.ensureVisible(find.text('请选择主播'));
  await tester.tap(find.text('请选择主播'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('主播A'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, (call) async {
      if (call.method == 'getGroupMemberList' ||
          call.method == 'getGroupMembersInfo') {
        return jsonEncode([
          {
            'userID': 'anchor',
            'groupID': 'group#1',
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

  testWidgets(
      'default management returns from ended push with creation available again',
      (tester) async {
    var created = false, ended = false;
    final revokeResult = Completer<Map<String, dynamic>>();
    final transport = LiveTransport((request) {
      if (request.path.endsWith('/current')) {
        return {
          'active': created && !ended,
          if (created && !ended) 'session': liveDTO()
        };
      }
      if (request.path.endsWith('/authorize')) {
        created = true;
        return {
          ...liveDTO(),
          'groupFeatures': _summary(),
          'imSyncStatus': 'pending'
        };
      }
      if (request.path.endsWith('/revoke')) {
        ended = true;
        return revokeResult.future;
      }
      if (request.path.endsWith('/push-info')) return _push('created-key');
      return liveDTO();
    });
    final fixture = _PermissionFixture(transport.api());
    addTearDown(fixture.events.close);
    final changed = <LiveSession>[];
    await _mount(
        tester,
        LiveManagePage(
            featureContext: fixture.snapshot, onStateChanged: changed.add));
    await _prepareCreate(tester);
    await tester.tap(find.text('开启直播'));
    await tester.pumpAndSettle();
    expect(find.byType(LivePushPage), findsOneWidget);
    expect(changed.single.status, LiveStatus.authorized);
    await tester.tap(find.text('撤销直播'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await _frames(tester);
    expect(
        transport.requests.where((request) => request.path.endsWith('/revoke')),
        hasLength(1));
    // The shared SDK summary arrives while the parent is waiting for push.
    // The parent's busy guard queues one calibration until push returns.
    fixture.acceptSummary(_summary(status: 'ended', revision: 2));
    await _frames(tester);
    revokeResult.complete({
      ...liveDTO(status: 'ENDED', version: 2),
      'groupFeatures': _summary(status: 'ended', revision: 2),
      'imSyncStatus': 'pending'
    });
    // Flush the transport and route result before the queued 250 ms refresh.
    // The typed result must repair the parent without depending on that GET.
    final parent = find.byType(LiveManagePage, skipOffstage: false);
    final createButton = find.descendant(
        of: parent,
        matching: find.byType(LivePrimaryButton, skipOffstage: false),
        skipOffstage: false);
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (createButton.evaluate().length == 1 &&
          tester.widget<LivePrimaryButton>(createButton).label == '开启直播') {
        break;
      }
    }
    expect(createButton, findsOneWidget,
        reason: 'The ended result must replace the active authorization form '
            'before the deferred current request.');
    expect(tester.widget<LivePrimaryButton>(createButton).label, '开启直播');
    expect(
        find.descendant(
            of: parent,
            matching: find.text('撤销直播', skipOffstage: false),
            skipOffstage: false),
        findsNothing);
    expect(
        transport.requests
            .where((request) => request.path.endsWith('/current')),
        hasLength(1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(LivePushPage, skipOffstage: false), findsNothing);
    expect(find.byType(LiveManagePage).hitTestable(), findsOneWidget);
    expect(find.text('开启直播'), findsOneWidget);
    expect(find.text('撤销直播'), findsNothing);
    expect(find.text('结束直播'), findsNothing);
    expect(find.text('查看推流地址'), findsNothing);
    expect(
        tester
            .widget<LivePrimaryButton>(find.byType(LivePrimaryButton))
            .onPressed,
        isNotNull);
    expect(changed.map((session) => session.status),
        [LiveStatus.authorized, LiveStatus.ended]);
    expect(
        transport.requests
            .where((request) => request.path.endsWith('/authorize')),
        hasLength(1));
    expect(
        transport.requests.where((request) => request.path.endsWith('/revoke')),
        hasLength(1));
    // The queued SDK calibration reads the real inactive current state once;
    // it must not leave an old AUTHORIZED form or repeat a business mutation.
    expect(
        transport.requests
            .where((request) => request.path.endsWith('/current')),
        hasLength(2));
    await _unmount(tester);
    expect(tester.takeException(), isNull);
  });
}
