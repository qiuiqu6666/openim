import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/pages/live_manage_page.dart';
import 'package:openim/pages/group_features/live/pages/live_push_page.dart';
import 'package:openim/pages/group_features/live/pages/live_room_page.dart';
import 'package:openim/pages/group_features/live/pages/live_tip_sheet.dart';
import 'package:openim/pages/group_features/live/widgets/live_style.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim/services/fund_pending_store.dart';
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

class _Security extends StubSettingsService {
  @override
  Future<bool> hasTradePassword() async => true;
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
      'pending mirror create refreshes initially false push permission and navigates once',
      (tester) async {
    var created = false;
    final transport = LiveTransport((request) {
      if (request.path.endsWith('/current')) {
        return {'active': created, if (created) 'session': liveDTO()};
      }
      if (request.path.endsWith('/authorize')) {
        created = true;
        return {
          ...liveDTO(),
          'groupFeatures': _summary(),
          'imSyncStatus': 'pending'
        };
      }
      if (request.path.endsWith('/push-info')) return _push('created-key');
      return liveDTO();
    });
    final fixture = _PermissionFixture(transport.api());
    addTearDown(fixture.events.close);
    var saved = 0;
    await _mount(
        tester,
        LiveManagePage(
            featureContext: fixture.snapshot, onStateChanged: (_) => saved++));
    await _prepareCreate(tester);
    await tester.tap(find.text('开启直播'));
    await tester.pumpAndSettle();
    expect(find.byType(LivePushPage), findsOneWidget);
    final notice = find.text('直播设置已保存');
    expect(notice, findsOneWidget);
    expect(EasyLoading.isShow, isTrue);
    expect(find.byType(SnackBar), findsNothing);
    final overlay = find.ancestor(of: notice, matching: find.byType(Overlay));
    expect(overlay, findsOneWidget);
    final center = tester.getCenter(overlay);
    expect(tester.getCenter(notice).dx, closeTo(center.dx, 1));
    expect(tester.getCenter(notice).dy, closeTo(center.dy, 1));
    expect(
        find.text('rtmp://push.example.test/live/created-key'), findsOneWidget);
    expect(saved, 1);
    expect(
        transport.requests
            .where((request) => request.path.endsWith('/authorize')),
        hasLength(1));
    expect(fixture.refreshes, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  for (final unknown in [false, true]) {
    testWidgets(
        '${unknown ? 'unknown create' : '20069'} only calibrates current without second POST',
        (tester) async {
      var attempted = false;
      final scheduledUtc = DateTime.utc(2030, 6, 2, 2, 15);
      final actual = unknown
          ? {
              ...liveDTO(status: 'SCHEDULED'),
              'scheduledStartAt': scheduledUtc.toIso8601String()
            }
          : liveDTO();
      final transport = LiveTransport((request) {
        if (request.path.endsWith('/current')) {
          return {'active': attempted, if (attempted) 'session': actual};
        }
        if (request.path.endsWith('/authorize')) {
          attempted = true;
          if (unknown) {
            throw DioException(
                requestOptions: request,
                type: DioExceptionType.connectionError);
          }
          return {'errCode': 20069, 'errMsg': 'already active'};
        }
        return liveDTO();
      });
      final fixture = _PermissionFixture(transport.api());
      addTearDown(fixture.events.close);
      await _mount(tester, LiveManagePage(featureContext: fixture.snapshot));
      await _prepareCreate(tester);
      await tester.tap(find.text('开启直播'));
      await tester.pumpAndSettle();
      expect(
          transport.requests
              .where((request) => request.path.endsWith('/authorize')),
          hasLength(1));
      expect(
          transport.requests
              .where((request) => request.path.endsWith('/current')),
          hasLength(2));
      expect(find.byType(LivePushPage), findsNothing);
      expect(find.textContaining(unknown ? '创建结果尚未确认' : '该群已有未结束的直播'),
          findsOneWidget);
      expect(find.text('直播设置已保存'), findsNothing);
      if (unknown) {
        expect(
            find.text(
                DateFormat('yyyy-MM-dd HH:mm').format(scheduledUtc.toLocal())),
            findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  testWidgets(
      'unknown create with no confirmed session exposes only read-only retry',
      (tester) async {
    final transport = LiveTransport((request) {
      if (request.path.endsWith('/current')) return {'active': false};
      throw DioException(
          requestOptions: request, type: DioExceptionType.connectionError);
    });
    final fixture = _PermissionFixture(transport.api());
    addTearDown(fixture.events.close);
    await _mount(tester, LiveManagePage(featureContext: fixture.snapshot));
    await _prepareCreate(tester);
    await tester.tap(find.text('开启直播'));
    await tester.pumpAndSettle();
    expect(find.text('开启直播'), findsNothing);
    expect(find.text('刷新当前场次'), findsOneWidget);
    await tester.tap(find.text('刷新当前场次'));
    await tester.pumpAndSettle();
    expect(
        transport.requests
            .where((request) => request.path.endsWith('/authorize')),
        hasLength(1));
    expect(
        transport.requests
            .where((request) => request.path.endsWith('/current')),
        hasLength(3));
    expect(find.text('直播设置已保存'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'scheduled UTC details render and edit in local time while writes remain UTC',
      (tester) async {
    final scheduledUtc = DateTime.utc(2030, 6, 2, 2, 15);
    final scheduledLocal = scheduledUtc.toLocal();
    final replacementLocal = scheduledLocal.add(const Duration(hours: 1));
    Map<String, dynamic> scheduledDTO(DateTime at, {int version = 1}) => {
          ...liveDTO(status: 'SCHEDULED', version: version),
          'scheduledStartAt': at.toUtc().toIso8601String()
        };
    final transport = LiveTransport((request) {
      if (request.path.endsWith('/current')) {
        return {'active': true, 'session': scheduledDTO(scheduledUtc)};
      }
      if (request.path.endsWith('/schedule')) {
        return {
          ...scheduledDTO(replacementLocal, version: 2),
          'groupFeatures': _summary(status: 'scheduled', revision: 2),
          'imSyncStatus': 'pending'
        };
      }
      throw StateError('Unexpected request: ${request.path}');
    });
    final fixture = _PermissionFixture(transport.api());
    addTearDown(fixture.events.close);
    await _mount(tester, LiveManagePage(featureContext: fixture.snapshot));
    await tester.pumpAndSettle();
    final format = DateFormat('yyyy-MM-dd HH:mm');
    expect(find.text(format.format(scheduledLocal)), findsOneWidget);
    await tester.ensureVisible(find.text('预约开播'));
    await tester.tap(find.text('预约开播'));
    await tester.pumpAndSettle();
    final picker =
        tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
    expect(picker.initialDateTime.isUtc, isFalse);
    expect(picker.initialDateTime, scheduledLocal);
    // Asia/Taipei hosts display 02:15Z as 10:15. Keep the contract portable
    // for CI hosts while also checking that timezone explicitly when present.
    if (scheduledLocal.timeZoneOffset == const Duration(hours: 8)) {
      expect(scheduledLocal.hour, 10);
    }
    picker.onDateTimeChanged(replacementLocal);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();
    final request = transport.requests
        .singleWhere((request) => request.path.endsWith('/schedule'));
    expect((request.data as Map)['scheduledStartAt'],
        replacementLocal.toUtc().toIso8601String());
    expect(find.text(format.format(replacementLocal)), findsOneWidget);
    await tester.ensureVisible(find.text('预约开播'));
    await tester.tap(find.text('预约开播'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
            .initialDateTime
            .isUtc,
        isFalse);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('late current GET cannot replace a confirmed saved scene',
      (tester) async {
    final oldCurrent = Completer<Map<String, dynamic>>();
    var reads = 0;
    final transport = LiveTransport((request) async {
      if (request.path.endsWith('/current')) {
        reads++;
        if (reads == 2) return oldCurrent.future;
        return {'active': true, 'session': liveDTO(status: 'SCHEDULED')};
      }
      if (request.path.endsWith('/schedule')) {
        return {
          ...liveDTO(status: 'SCHEDULED', version: 2),
          'groupFeatures': _summary(status: 'scheduled', revision: 2),
          'imSyncStatus': 'pending'
        };
      }
      throw StateError('Unexpected request: ${request.path}');
    });
    final fixture = _PermissionFixture(transport.api());
    addTearDown(fixture.events.close);
    LiveSession? saved;
    await _mount(
        tester,
        LiveManagePage(
            featureContext: fixture.snapshot,
            onStateChanged: (session) => saved = session));
    await tester.pumpAndSettle();
    // A queued tap can retain this callback while an SDK-triggered GET starts.
    // The mutation must invalidate that GET independently of widget visibility.
    final save = tester
        .widget<LivePrimaryButton>(find.byType(LivePrimaryButton))
        .onPressed!;
    fixture.acceptSummary(_summary(status: 'scheduled'));
    await _frames(tester);
    expect(reads, 2);
    save();
    await _frames(tester);
    expect(saved?.version, 2);
    expect(find.text('保存修改'), findsOneWidget);
    oldCurrent.complete({'active': false});
    await tester.pumpAndSettle();
    expect(saved?.version, 2);
    expect(find.text('保存修改'), findsOneWidget);
    expect(find.text('开启直播'), findsNothing);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('live-room-name')))
            .controller!
            .text,
        '每日直播');
    expect(
        transport.requests
            .where((request) => request.path.endsWith('/schedule')),
        hasLength(1));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'same-session scheduled SDK mirror cannot block authorized push details',
      (tester) async {
    final transport = LiveTransport((request) =>
        request.path.endsWith('/push-info') ? _push('live-key') : liveDTO());
    final fixture = _PermissionFixture(transport.api(), canPush: true);
    addTearDown(fixture.events.close);
    await _mount(tester,
        LivePushPage(featureContext: fixture.snapshot, session: liveSession()));
    await tester.pumpAndSettle();
    fixture.acceptSummary(_summary(status: 'scheduled'));
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(find.text('rtmp://push.example.test/live/live-key'), findsOneWidget);
    expect(
        transport.requests
            .where((request) => request.path.endsWith('/push-info')),
        hasLength(2));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'push revocation clears late key and current permissions recover without reopening',
      (tester) async {
    final oldKey = Completer<Map<String, dynamic>>();
    var pushes = 0;
    final transport = LiveTransport((request) async {
      if (request.path.endsWith('/push-info')) {
        pushes++;
        if (pushes == 1) return await oldKey.future;
        return _push('new-key');
      }
      return liveDTO();
    });
    final fixture = _PermissionFixture(transport.api(), canPush: true);
    addTearDown(fixture.events.close);
    await _mount(tester,
        LivePushPage(featureContext: fixture.snapshot, session: liveSession()));
    await _frames(tester);
    expect(pushes, 1);
    fixture.change(push: false);
    await _frames(tester);
    fixture.change(push: true);
    await _frames(tester);
    expect(pushes,
        1); // Revalidation joins while the old private request is pending.
    oldKey.complete(_push('late-revoked-key'));
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('late-revoked-key'), findsNothing);
    expect(find.text('rtmp://push.example.test/live/new-key'), findsOneWidget);
    expect(find.textContaining('late-revoked-key'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'background drops push secret and defers private refresh until foreground',
      (tester) async {
    final transport = LiveTransport((request) =>
        request.path.endsWith('/push-info') ? _push('private-key') : liveDTO());
    final fixture = _PermissionFixture(transport.api(), canPush: true);
    addTearDown(fixture.events.close);
    await _mount(tester,
        LivePushPage(featureContext: fixture.snapshot, session: liveSession()));
    await tester.pumpAndSettle();
    expect(find.textContaining('private-key'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await tester.pump();
    final requests = transport.requests.length, refreshes = fixture.refreshes;
    fixture.change(push: true);
    await _frames(tester);
    // Paused lifecycle disables scheduled frames. Render the already-cleared
    // state without resuming, so the assertion also proves no private refresh.
    tester.binding.scheduleWarmUpFrame();
    expect(find.textContaining('private-key'), findsNothing);
    expect(transport.requests.length, requests);
    expect(fixture.refreshes, refreshes);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('private-key'), findsOneWidget);
    expect(fixture.refreshes, greaterThan(refreshes));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'own terminal summary cannot suppress confirmed end result or keep push key',
      (tester) async {
    var ended = false;
    final transport = LiveTransport((request) {
      if (request.path.endsWith('/push-info')) return _push('private-key');
      if (request.path.endsWith('/revoke')) {
        ended = true;
        return {
          ...liveDTO(status: 'ENDED', version: 2),
          'groupFeatures': _summary(status: 'ended', revision: 2),
          'imSyncStatus': 'pending'
        };
      }
      return liveDTO(
          status: ended ? 'ENDED' : 'AUTHORIZED', version: ended ? 2 : 1);
    });
    final fixture = _PermissionFixture(transport.api(), canPush: true);
    addTearDown(fixture.events.close);
    LiveSession? confirmed;
    await _mount(
        tester,
        LivePushPage(
            featureContext: fixture.snapshot,
            session: liveSession(),
            onStateChanged: (session) => confirmed = session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销直播'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(confirmed?.status, LiveStatus.ended);
    expect(find.textContaining('private-key'), findsNothing);
    expect(find.textContaining('直播已结束'), findsWidgets);
    expect(
        transport.requests.where((request) => request.path.endsWith('/revoke')),
        hasLength(1));
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'waiting room adopts resolved push permission while preserving public waiting view',
      (tester) async {
    final transport = LiveTransport((_) => liveDTO());
    final fixture = _PermissionFixture(transport.api());
    addTearDown(fixture.events.close);
    await _mount(tester,
        LiveRoomPage(featureContext: fixture.snapshot, session: liveSession()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('推流信息'), findsNothing);
    fixture.change(push: true);
    await tester.pumpAndSettle();
    expect(find.byTooltip('推流信息'), findsOneWidget);
    expect(find.textContaining('直播准备中'), findsOneWidget);
    expect(find.byTooltip('打赏主播'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  for (final live in [false, true]) {
    testWidgets(
        'tip button requires true LIVE and disables on terminal summary ($live)',
        (tester) async {
      final transport =
          LiveTransport((_) => throw StateError('must not send a tip'));
      final fixture = _PermissionFixture(transport.api());
      addTearDown(fixture.events.close);
      await _mount(
          tester,
          Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => GroupLiveTipSheet.show(context,
                          featureContext: fixture.snapshot,
                          session: liveSession(
                              status: live
                                  ? LiveStatus.live
                                  : LiveStatus.authorized),
                          security: _Security()),
                      child: const Text('打开打赏')))));
      await tester.tap(find.text('打开打赏'));
      await tester.pumpAndSettle();
      LivePrimaryButton button() =>
          tester.widget<LivePrimaryButton>(find.byType(LivePrimaryButton));
      expect(button().onPressed != null, live);
      if (live) {
        fixture.acceptSummary(_summary(status: 'ended', revision: 2));
        await tester.pumpAndSettle();
        expect(button().onPressed, isNull);
      }
      expect(transport.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  testWidgets(
      'confirmed LIVE permits tips through same-session pre-live SDK lag',
      (tester) async {
    final transport =
        LiveTransport((_) => throw StateError('must not send a tip'));
    final fixture = _PermissionFixture(transport.api())
      ..features = GroupFeatures.fromJson(_summary());
    addTearDown(fixture.events.close);
    await _mount(
        tester,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => GroupLiveTipSheet.show(context,
                        featureContext: fixture.snapshot,
                        session: liveSession(status: LiveStatus.live),
                        security: _Security()),
                    child: const Text('打开打赏')))));
    await tester.tap(find.text('打开打赏'));
    await tester.pumpAndSettle();
    LivePrimaryButton button() =>
        tester.widget<LivePrimaryButton>(find.byType(LivePrimaryButton));
    expect(button().onPressed, isNotNull);
    fixture.acceptSummary(_summary(status: 'scheduled', revision: 2));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNotNull);
    fixture.acceptSummary(_summary(status: 'ended', revision: 3));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNull);
    expect(transport.requests, isEmpty);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('20062 preserves the pending tip and its original order on retry',
      (tester) async {
    final transport =
        LiveTransport((_) => {'errCode': 20062, 'errMsg': '订单参数冲突'});
    final fixture = _PermissionFixture(transport.api());
    addTearDown(fixture.events.close);
    final store = FundPendingStore(accountKey: 'https://example.test:self');
    await _mount(
        tester,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => GroupLiveTipSheet.show(context,
                        featureContext: fixture.snapshot,
                        session: liveSession(status: LiveStatus.live),
                        security: _Security(),
                        pendingStore: store),
                    child: const Text('打开打赏')))));
    await tester.tap(find.text('打开打赏'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1');
    await tester.tap(find.text('确认打赏'));
    await _frames(tester);
    for (final digit in '123456'.split('')) {
      await tester.tap(find.byKey(ValueKey('trade-password-key-$digit')));
      await tester.pump();
    }
    await _frames(tester);
    expect(transport.requests, hasLength(1));
    final order = (transport.requests.single.data as Map)['clientOrderId'];
    await tester.tap(find.byKey(const ValueKey('payment-cancel')));
    await _frames(tester);
    expect(find.text('重试原交易'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse);
    await tester.tap(find.text('重试原交易'));
    await _frames(tester);
    for (final digit in '123456'.split('')) {
      await tester.tap(find.byKey(ValueKey('trade-password-key-$digit')));
      await tester.pump();
    }
    await _frames(tester);
    expect(transport.requests, hasLength(2));
    expect((transport.requests.last.data as Map)['clientOrderId'], order);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
}
