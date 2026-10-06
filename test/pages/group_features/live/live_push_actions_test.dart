import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/pages/live_push_page.dart';
import 'package:openim/pages/group_features/live/widgets/live_style.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim_common/openim_common.dart';

import 'live_test_support.dart';

Map<String, dynamic> _endedResponse() => {
      ...liveDTO(status: 'ENDED', version: 2),
      'imSyncStatus': 'pending',
      'groupFeatures': {
        'schemaVersion': 1,
        'revision': 2,
        'live': {
          'status': 'ended',
          'sessionID': 'live-1',
          'anchorUserID': 'anchor'
        },
        'games': {
          'sangong': {'enabled': false},
          'markSix': {'enabled': false}
        }
      }
    };

Map<String, dynamic> _push(
        {bool expired = false, String key = 'private-key'}) =>
    {
      'rtmpServer': 'rtmp://push.example.test/live',
      'streamKey': key,
      'expiresAt': (expired
              ? DateTime.now().subtract(const Duration(minutes: 1))
              : DateTime.now().add(const Duration(hours: 1)))
          .toUtc()
          .toIso8601String()
    };

Future<void> _unmount(WidgetTester tester) async {
  await EasyLoading.dismiss(animation: false);
  await tester.pump();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> _mountPush(WidgetTester tester,
    {required GroupFeatureContext featureContext,
    LiveStatus status = LiveStatus.authorized,
    ValueChanged<LiveSession>? onStateChanged,
    ValueChanged<LiveSession?>? onReturned}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  configureEasyLoadingInteractions();
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: EasyLoading.init(),
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () async {
                        final result = await Navigator.of(context)
                            .push<LiveSession>(MaterialPageRoute<LiveSession>(
                                builder: (_) => LivePushPage(
                                    featureContext: featureContext,
                                    session: liveSession(status: status),
                                    onStateChanged: onStateChanged)));
                        onReturned?.call(result);
                      },
                      child: const Text('打开推流页')))))));
  await tester.pump();
  addTearDown(() => _unmount(tester));
  await tester.tap(find.text('打开推流页'));
  await tester.pumpAndSettle();
}

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder get _bottomButton => find.byType(LivePrimaryButton);
Finder get _refreshButton => find.ancestor(
    of: find.byTooltip('刷新状态'), matching: find.byType(IconButton));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());

  for (final status in [
    LiveStatus.scheduled,
    LiveStatus.authorized,
    LiveStatus.live
  ]) {
    testWidgets(
        'single primary ${status.name} action confirms the real endpoint',
        (tester) async {
      final live = status == LiveStatus.live;
      final label = live ? '结束直播' : '撤销直播';
      final endpoint = live ? '/stop' : '/revoke';
      final events = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(events.close);
      var permissionsCurrent = true;
      final transport = LiveTransport((request) {
        if (request.path.endsWith(endpoint)) return _endedResponse();
        if (request.path.endsWith('/push-info')) return _push();
        return liveDTO(status: status.name.toUpperCase());
      });
      final feature = liveContext(transport.api(),
          capabilitiesCurrent: () => permissionsCurrent,
          onFeaturesChanged: (summary) {
            // Its own committed summary invalidates the captured permission
            // epoch; the confirmed result must still return to this account.
            permissionsCurrent = false;
            events.add({
              'key': 'groupFeaturesChanged',
              'groupID': 'group#1',
              'data': {'groupFeatures': summary}
            });
          },
          events: events.stream);
      final changed = <LiveSession>[];
      LiveSession? returned;
      await _mountPush(tester,
          featureContext: feature,
          status: status,
          onStateChanged: changed.add,
          onReturned: (session) => returned = session);
      expect(_bottomButton, findsOneWidget);
      expect(tester.widget<LivePrimaryButton>(_bottomButton).label, label);
      expect(find.text(label), findsOneWidget); // No duplicate red text action.
      expect(find.text('刷新状态'), findsNothing);
      expect(find.byTooltip('刷新状态'), findsOneWidget);
      final button = find.descendant(
          of: _bottomButton, matching: find.byType(FilledButton));
      expect(
          tester
              .widget<FilledButton>(button)
              .style!
              .backgroundColor!
              .resolve({}),
          LiveStyle.blue);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
          transport.requests.where((r) => r.path.endsWith(endpoint)), isEmpty);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(changed, hasLength(1));
      expect(changed.single.status, LiveStatus.ended);
      expect(returned?.status, LiveStatus.ended);
      expect(find.byType(LivePushPage), findsNothing);
      expect(find.text('打开推流页'), findsOneWidget);
      expect(find.textContaining('private-key'), findsNothing);
      expect(transport.requests.where((r) => r.path.endsWith(endpoint)),
          hasLength(1));
      expect(
          transport.requests
              .where((r) => r.path.endsWith(live ? '/revoke' : '/stop')),
          isEmpty);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  testWidgets('top refresh opens scheduled credentials and renews expired keys',
      (tester) async {
    var status = 'SCHEDULED';
    var keys = 0;
    final transport = LiveTransport((request) {
      if (request.path.endsWith('/push-info')) {
        keys++;
        return _push(expired: keys == 1, key: 'key-$keys');
      }
      return liveDTO(status: status, version: status == 'SCHEDULED' ? 1 : 2);
    });
    await _mountPush(tester,
        featureContext: liveContext(transport.api()),
        status: LiveStatus.scheduled);
    expect(find.text('直播已预约'), findsOneWidget);
    expect(keys, 0);
    status = 'AUTHORIZED';
    await tester.tap(find.byTooltip('刷新状态'));
    await tester.pumpAndSettle();
    expect(keys, 1);
    expect(find.text('推流地址已过期，请刷新'), findsOneWidget);
    await tester.tap(find.byTooltip('刷新状态'));
    await tester.pumpAndSettle();
    expect(keys, 2);
    expect(find.text('rtmp://push.example.test/live/key-2'), findsOneWidget);
    expect(tester.widget<LivePrimaryButton>(_bottomButton).label, '撤销直播');
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'manager without push permission can revoke without requesting keys',
      (tester) async {
    final transport = LiveTransport((request) =>
        request.path.endsWith('/revoke') ? _endedResponse() : liveDTO());
    await _mountPush(tester,
        featureContext: liveContext(transport.api(),
            permissions: const GroupLiveCapabilities(canManage: true)));
    expect(find.text('没有获取推流信息的权限'), findsOneWidget);
    expect(find.text('撤销直播'), findsOneWidget);
    expect(transport.requests.where((r) => r.path.endsWith('/push-info')),
        isEmpty);
    await tester.tap(find.text('撤销直播'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(transport.requests.where((r) => r.path.endsWith('/revoke')),
        hasLength(1));
    expect(find.byType(LivePushPage), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('revoked permission while confirming never sends end request',
      (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    var permitted = true;
    final transport = LiveTransport(
        (request) => request.path.endsWith('/push-info') ? _push() : liveDTO());
    await _mountPush(tester,
        featureContext: liveContext(transport.api(),
            capabilitiesCurrent: () => permitted, events: events.stream));
    await tester.tap(find.text('撤销直播'));
    await tester.pumpAndSettle();
    permitted = false;
    events.add(
        {'key': 'groupFeatureCapabilitiesInvalidated', 'groupID': 'group#1'});
    await tester.pump();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(
        transport.requests.where((r) => r.path.endsWith('/revoke')), isEmpty);
    expect(find.byType(LivePushPage), findsOneWidget);
    expect(tester.widget<LivePrimaryButton>(_bottomButton).onPressed, isNull);
    expect(find.textContaining('private-key'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('busy end submits once and a failure preserves the current route',
      (tester) async {
    final result = Completer<Map<String, dynamic>>();
    final transport = LiveTransport((request) {
      if (request.path.endsWith('/revoke')) return result.future;
      if (request.path.endsWith('/push-info')) return _push();
      return liveDTO();
    });
    var changed = 0;
    await _mountPush(tester,
        featureContext: liveContext(transport.api()),
        onStateChanged: (_) => changed++);
    final staleAction =
        tester.widget<LivePrimaryButton>(_bottomButton).onPressed!;
    await tester.tap(find.text('撤销直播'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await _frames(tester);
    expect(tester.widget<LivePrimaryButton>(_bottomButton).busy, isTrue);
    expect(tester.widget<LivePrimaryButton>(_bottomButton).onPressed, isNull);
    expect(tester.widget<IconButton>(_refreshButton).onPressed, isNull);
    staleAction();
    await tester.pump();
    expect(transport.requests.where((r) => r.path.endsWith('/revoke')),
        hasLength(1));
    result.complete({'errCode': 20070, 'errMsg': 'state conflict'});
    await tester.pumpAndSettle();
    expect(changed, 0);
    expect(find.byType(LivePushPage), findsOneWidget);
    expect(find.textContaining('当前直播状态不允许此操作'), findsOneWidget);
    expect(tester.widget<LivePrimaryButton>(_bottomButton).busy, isFalse);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'an authorized confirmation cannot revoke a session that becomes live',
      (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    var status = 'AUTHORIZED';
    final transport = LiveTransport((request) {
      if (request.path.endsWith('/stop')) return _endedResponse();
      if (request.path.endsWith('/push-info')) return _push();
      return liveDTO(status: status, version: status == 'LIVE' ? 2 : 1);
    });
    await _mountPush(tester,
        featureContext: liveContext(transport.api(), events: events.stream));
    await tester.tap(find.text('撤销直播'));
    await tester.pumpAndSettle();
    expect(find.text('确认撤销这场直播吗？'), findsOneWidget);
    status = 'LIVE';
    events.add({
      'key': 'groupFeaturesChanged',
      'groupID': 'group#1',
      'data': {
        'groupFeatures': {
          'schemaVersion': 1,
          'revision': 2,
          'live': {
            'status': 'live',
            'sessionID': 'live-1',
            'anchorUserID': 'anchor'
          },
          'games': {
            'sangong': {'enabled': false},
            'markSix': {'enabled': false}
          }
        }
      }
    });
    await _frames(tester);
    expect(tester.widget<LivePrimaryButton>(_bottomButton).label, '结束直播');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(
        transport.requests.where(
            (r) => r.path.endsWith('/revoke') || r.path.endsWith('/stop')),
        isEmpty);
    expect(find.byType(LivePushPage), findsOneWidget);
    await tester.tap(find.text('结束直播'));
    await tester.pumpAndSettle();
    expect(find.text('确认结束直播吗？结束后请在 OBS 中停止推流。'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(transport.requests.where((r) => r.path.endsWith('/stop')),
        hasLength(1));
    expect(
        transport.requests.where((r) => r.path.endsWith('/revoke')), isEmpty);
    expect(find.byType(LivePushPage), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
      'live summary during permission refresh cancels revoke and recalibrates',
      (tester) async {
    final events = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(events.close);
    final refreshed = Completer<GroupFeatureContext>();
    var status = 'AUTHORIZED';
    final transport = LiveTransport((request) {
      if (request.path.endsWith('/push-info')) return _push();
      return liveDTO(status: status, version: status == 'LIVE' ? 2 : 1);
    });
    final base = liveContext(transport.api());
    var refreshes = 0;
    late final GroupFeatureContext feature;
    feature = GroupFeatureContext(
        groupID: base.groupID,
        groupName: base.groupName,
        currentUserID: base.currentUserID,
        api: base.api,
        capabilities: base.capabilities,
        sessionCurrent: () => true,
        onFeaturesChanged: (_) {},
        events: events.stream,
        reloadCapabilities: (_) {
          refreshes++;
          return refreshes == 2 ? refreshed.future : Future.value(feature);
        });
    await _mountPush(tester, featureContext: feature);
    await tester.tap(find.text('撤销直播'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await _frames(tester);
    expect(refreshes, 2);
    expect(tester.widget<LivePrimaryButton>(_bottomButton).busy, isTrue);
    status = 'LIVE';
    events.add({
      'key': 'groupFeaturesChanged',
      'groupID': 'group#1',
      'data': {
        'groupFeatures': {
          'schemaVersion': 1,
          'revision': 2,
          'live': {
            'status': 'live',
            'sessionID': 'live-1',
            'anchorUserID': 'anchor'
          },
          'games': {
            'sangong': {'enabled': false},
            'markSix': {'enabled': false}
          }
        }
      }
    });
    await _frames(tester);
    expect(transport.requests.where((r) => r.path.endsWith('/live/live-1')),
        hasLength(1));
    refreshed.complete(feature);
    await _frames(tester);
    await tester.pumpAndSettle();
    expect(
        transport.requests.where(
            (r) => r.path.endsWith('/revoke') || r.path.endsWith('/stop')),
        isEmpty);
    expect(transport.requests.where((r) => r.path.endsWith('/live/live-1')),
        hasLength(2));
    expect(refreshes, 3);
    expect(tester.widget<LivePrimaryButton>(_bottomButton).busy, isFalse);
    expect(tester.widget<LivePrimaryButton>(_bottomButton).label, '结束直播');
    expect(find.byType(LivePushPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('successful end does not dismiss a covering tutorial route',
      (tester) async {
    final result = Completer<Map<String, dynamic>>();
    final transport = LiveTransport((request) {
      if (request.path.endsWith('/revoke')) return result.future;
      if (request.path.endsWith('/push-info')) return _push();
      return liveDTO();
    });
    final changed = <LiveSession>[];
    LiveSession? returned;
    await _mountPush(tester,
        featureContext: liveContext(transport.api()),
        onStateChanged: changed.add,
        onReturned: (session) => returned = session);
    await tester.tap(find.text('撤销直播'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await _frames(tester);
    await tester.ensureVisible(find.text('直播教程'));
    await tester.tap(find.text('直播教程'));
    await _frames(tester);
    expect(find.text('我知道了'), findsOneWidget);
    result.complete(_endedResponse());
    await tester.pumpAndSettle();
    expect(changed.single.status, LiveStatus.ended);
    expect(find.text('我知道了'), findsOneWidget);
    expect(find.byType(LivePushPage), findsOneWidget);
    await tester.ensureVisible(find.text('我知道了'));
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(find.text('我知道了'), findsNothing);
    expect(find.byType(LivePushPage), findsNothing);
    expect(find.text('打开推流页'), findsOneWidget);
    expect(changed, hasLength(1));
    expect(returned?.status, LiveStatus.ended);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('background end success publishes and returns once on resume',
      (tester) async {
    final result = Completer<Map<String, dynamic>>();
    final transport = LiveTransport((request) {
      if (request.path.endsWith('/revoke')) return result.future;
      if (request.path.endsWith('/push-info')) return _push();
      return liveDTO();
    });
    var permissionCurrent = true;
    final changed = <LiveSession>[];
    LiveSession? returned;
    await _mountPush(tester,
        featureContext: liveContext(transport.api(),
            capabilitiesCurrent: () => permissionCurrent,
            onFeaturesChanged: (_) => permissionCurrent = false),
        onStateChanged: changed.add,
        onReturned: (session) => returned = session);
    try {
      await tester.tap(find.text('撤销直播'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await _frames(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.scheduleWarmUpFrame();
      expect(find.textContaining('private-key'), findsNothing);
      result.complete(_endedResponse());
      await _frames(tester);
      expect(changed, isEmpty);
      expect(returned, isNull);
      expect(find.byType(LivePushPage), findsOneWidget);
      final requests = transport.requests.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(changed, hasLength(1));
      expect(changed.single.status, LiveStatus.ended);
      expect(returned?.status, LiveStatus.ended);
      expect(find.byType(LivePushPage), findsNothing);
      expect(find.text('打开推流页'), findsOneWidget);
      expect(transport.requests.length, requests);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(changed, hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _unmount(tester);
    }
  });
}
