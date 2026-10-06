import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/live/group_live_module.dart';
import 'package:openim/pages/group_features/live/widgets/live_banner.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/widgets/group_live_avatar.dart';
import 'package:openim_common/openim_common.dart';

import 'live_test_support.dart';

const _group = 'group#1';
const _sdk = MethodChannel('flutter_openim_sdk');

Map<String, dynamic> _summary(int revision,
        {String id = 'live-1', String status = 'ready'}) =>
    {
      'schemaVersion': 1,
      'revision': revision,
      'live': {
        'sessionID': id,
        'status': status,
        'roomName': '每日直播',
        'description': '和大家边看边聊',
        'anchorUserID': 'anchor',
      },
      'games': {'sangong': {}, 'markSix': {}},
    };

GroupInfo _mirror(Map<String, dynamic> summary) =>
    GroupInfo(groupID: _group, ex: jsonEncode({'groupFeatures': summary}));

Map<String, dynamic> _current(
        {bool active = true,
        String id = 'live-1',
        String status = 'AUTHORIZED',
        Map<String, dynamic>? summary}) =>
    {
      'active': active,
      if (active) 'session': liveDTO(id: id, status: status),
      if (summary != null) 'groupFeatures': summary,
    };

GroupFeatureStore _store(LiveTransport transport) => GroupFeatureStore(
    api: transport.api(),
    sessionCurrent: () => true,
    fetchGroups: (_) async => []);

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _mount(WidgetTester tester, GroupFeatureStore store,
    {bool dark = false, bool settle = true}) async {
  tester.view.physicalSize = const Size(390, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = dark;
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
              body: ListenableBuilder(
                  listenable: store,
                  builder: (_, __) => Column(children: [
                        GroupLiveAvatar(
                            store: store,
                            groupID: _group,
                            child: const SizedBox.square(dimension: 48)),
                        GroupLiveFeatureHost(
                            featureContext: store.context(
                                id: _group,
                                name: '直播群',
                                userID: 'self',
                                admin: true,
                                current: () => true)),
                      ]))))));
  if (settle) await _frames(tester);
}

Future<void> _unmount(WidgetTester tester, GroupFeatureStore store) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  store.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, (_) async => '[]');
  });
  tearDown(() {
    Get.reset();
    Styles.isDark = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdk, null);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'current summary without imSyncStatus populates chat and avatar and survives old mirrors dark=$dark',
        (tester) async {
      final summary = _summary(2);
      final transport = LiveTransport((_) => _current(summary: summary));
      final store = _store(transport);
      await _mount(tester, store, dark: dark);
      addTearDown(() => _unmount(tester, store));

      expect(find.byType(GroupLiveBanner), findsOneWidget);
      expect(find.text('有直播'), findsOneWidget);
      expect(store.features(_group).revision, 2);
      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.path, endsWith('/current'));

      store.seed(GroupInfo(groupID: _group, ex: ''));
      store.seed(_mirror(_summary(1, id: '', status: 'none')));
      await _frames(tester);
      expect(store.features(_group).revision, 2);
      expect(find.byType(GroupLiveBanner), findsOneWidget);
      expect(find.text('有直播'), findsOneWidget);
      expect(transport.requests, hasLength(1));

      store.seed(_mirror(summary));
      store.seed(
          GroupInfo(groupID: _group, ex: 'malformed after mirror synced'));
      await _frames(tester);
      expect(store.features(_group).valid, isFalse);
      expect(find.byType(GroupLiveBanner), findsNothing);
      expect(find.text('有直播'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final sameScene in [false, true]) {
    testWidgets(
        'initial current with older summary cannot replace accepted ${sameScene ? 'live status' : 'scene'}',
        (tester) async {
      final acceptedID = sameScene ? 'live-1' : 'live-2';
      final transport = LiveTransport((_) => _current(summary: _summary(1)));
      final store = _store(transport)
        ..seed(_mirror(_summary(2, id: acceptedID, status: 'live')));
      await _mount(tester, store);
      addTearDown(() => _unmount(tester, store));

      final banner =
          tester.widget<GroupLiveBanner>(find.byType(GroupLiveBanner));
      expect(banner.session.id, acceptedID);
      expect(banner.session.status, LiveStatus.live);
      expect(store.features(_group).revision, 2);
      expect(find.text('直播中'), findsOneWidget);
      expect(transport.requests, hasLength(1));
      expect(find.text('重试'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('current without summary can advance cached ready to actual LIVE',
      (tester) async {
    final transport = LiveTransport((_) => _current(status: 'LIVE'));
    final store = _store(transport)..seed(_mirror(_summary(2)));
    await _mount(tester, store);
    addTearDown(() => _unmount(tester, store));

    final banner = tester.widget<GroupLiveBanner>(find.byType(GroupLiveBanner));
    expect(banner.session.status, LiveStatus.live);
    expect(store.features(_group).revision, 2);
    expect(transport.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('current without summary can end a cached active chat banner',
      (tester) async {
    final transport = LiveTransport((_) => _current(active: false));
    final store = _store(transport)..seed(_mirror(_summary(2, status: 'live')));
    await _mount(tester, store);
    addTearDown(() => _unmount(tester, store));

    expect(find.byType(GroupLiveBanner), findsNothing);
    expect(transport.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final active in [true, false]) {
    testWidgets(
        'reopening starts from the accepted ${active ? 'active' : 'inactive'} projection before current replies',
        (tester) async {
      final reply = Completer<Map<String, dynamic>>();
      var reads = 0;
      final transport = LiveTransport((_) => ++reads == 1
          ? _current(active: active, status: 'LIVE')
          : reply.future);
      final store = _store(transport);
      if (!active) store.seed(_mirror(_summary(2, status: 'live')));
      addTearDown(() => _unmount(tester, store));
      await _mount(tester, store);
      expect(store.liveFeature(_group).isActive, active);
      if (active) {
        expect(store.features(_group).valid, false);
      } else {
        expect(store.features(_group).live.isActive, true);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await _mount(tester, store, settle: false);
      expect(
          find.byType(GroupLiveBanner), active ? findsOneWidget : findsNothing);
      if (active) {
        final banner =
            tester.widget<GroupLiveBanner>(find.byType(GroupLiveBanner));
        expect(banner.session.status, LiveStatus.live);
      }
      await _frames(tester);
      expect(reads, 2);
      expect(
          find.byType(GroupLiveBanner), active ? findsOneWidget : findsNothing);
      reply.complete(_current(active: active, status: 'LIVE'));
      await _frames(tester);
      expect(
          find.byType(GroupLiveBanner), active ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('capability and old mirror rebuilds preserve the live DTO',
      (tester) async {
    final transport = LiveTransport((_) => {
          'active': true,
          'session': liveDTO(status: 'LIVE', version: 7),
        });
    final store = _store(transport)..seed(_mirror(_summary(3)));
    addTearDown(() => _unmount(tester, store));
    await _mount(tester, store);
    final accepted =
        tester.widget<GroupLiveBanner>(find.byType(GroupLiveBanner)).session;
    expect(accepted.version, 7);
    store.invalidateCapabilities(_group);
    store.seed(_mirror(_summary(2, id: 'older-live')));
    await _frames(tester);
    final unchanged =
        tester.widget<GroupLiveBanner>(find.byType(GroupLiveBanner)).session;
    expect(unchanged, same(accepted));
    expect(transport.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an accepted projection cancels an older initial current read',
      (tester) async {
    final reply = Completer<Map<String, dynamic>>();
    final transport = LiveTransport((_) => reply.future);
    final store = _store(transport);
    addTearDown(() => _unmount(tester, store));
    await _mount(tester, store);
    expect(transport.requests, hasLength(1));
    store.applyLiveState(
        _group,
        const GroupLiveFeature(
            status: 'live', sessionID: 'new-live', roomName: '新直播间'));
    await _frames(tester);
    expect(
        tester.widget<GroupLiveBanner>(find.byType(GroupLiveBanner)).session.id,
        'new-live');
    reply.complete(_current());
    await _frames(tester);
    expect(
        tester.widget<GroupLiveBanner>(find.byType(GroupLiveBanner)).session.id,
        'new-live');
    expect(store.liveFeature(_group).sessionID, 'new-live');
    expect(tester.takeException(), isNull);
  });

  testWidgets('older current session versions cannot regress the live display',
      (tester) async {
    var reads = 0;
    final transport = LiveTransport((_) => switch (++reads) {
          1 => {'active': true, 'session': liveDTO(status: 'LIVE', version: 7)},
          2 => {
              'active': true,
              'session': liveDTO(status: 'AUTHORIZED', version: 6)
            },
          3 => {'active': true, 'session': liveDTO(status: 'LIVE', version: 8)},
          _ => {'active': false},
        });
    final store = _store(transport);
    addTearDown(() => _unmount(tester, store));
    await _mount(tester, store);
    final accepted =
        tester.widget<GroupLiveBanner>(find.byType(GroupLiveBanner)).session;
    expect(accepted.status, LiveStatus.live);
    final publications = <String>[];
    store.addListener(() => publications.add(store.liveFeature(_group).status));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester);
    expect(reads, 2);
    expect(store.liveFeature(_group).status, 'live');
    final banner = tester.widget<GroupLiveBanner>(find.byType(GroupLiveBanner));
    expect(banner.session, same(accepted));
    expect(banner.session.version, 7);
    expect(publications, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester);
    expect(reads, 3);
    expect(
        tester
            .widget<GroupLiveBanner>(find.byType(GroupLiveBanner))
            .session
            .version,
        8);
    expect(store.liveFeature(_group).status, 'live');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester);
    expect(reads, 4);
    expect(find.byType(GroupLiveBanner), findsNothing);
    expect(store.liveFeature(_group).isActive, false);
    expect(publications, ['none']);
    expect(tester.takeException(), isNull);
  });
}
