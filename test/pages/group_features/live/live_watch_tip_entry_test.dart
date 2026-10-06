import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/widgets/live_watch_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'live_test_support.dart';

Future<void> _unmount(WidgetTester tester) async {
  await EasyLoading.dismiss(animation: false);
  await tester.pump();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Map<String, dynamic> _features(int revision, {String status = 'live'}) => {
      'schemaVersion': 1,
      'revision': revision,
      'live': {
        'status': status,
        'sessionID': 'live-1',
        'roomName': '每日直播',
        'anchorUserID': 'anchor',
      },
      'games': {},
    };

void main() {
  late LiveTransport transport;
  late GroupFeatureStore store;
  var tipped = false;
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    tipped = false;
    transport = LiveTransport((request) {
      if (request.path.endsWith('/feature-capabilities')) {
        return {
          'errCode': 0,
          'data': {
            'groupID': 'group#1',
            'capabilityVersion': 1,
            'cacheTTLSeconds': 300,
            'live': {
              'canTip': true,
              'tipCurrencies': [
                {'code': 'BI99', 'label': '99BI', 'decimals': 2},
              ],
            },
          },
        };
      }
      if (request.path.endsWith('/play-info')) {
        return {
          'liveSessionId': 'live-1',
          'roomName': '每日直播',
          'protocol': 'hls',
          'playUrl': 'https://video.example.test/live.m3u8',
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
        };
      }
      if (request.path.endsWith('/tip')) {
        tipped = true;
        return {'tipId': 1, 'liveSessionId': 'live-1'};
      }
      return liveDTO(status: 'LIVE');
    });
    store = GroupFeatureStore(
        api: transport.api(),
        sessionCurrent: () => true,
        fetchGroups: (_) async => []);
    store.apply('group#1', _features(1));
  });
  tearDown(() {
    store.dispose();
    Get.reset();
  });

  Future<void> frames(WidgetTester tester) async {
    for (var frame = 0; frame < 8; frame++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> mount(WidgetTester tester, {bool dark = false}) async {
    await store.loadCapabilities('group#1');
    final featureContext = store.context(
        id: 'group#1',
        name: '直播群',
        userID: 'self',
        admin: false,
        current: () => true);
    configureEasyLoadingInteractions();
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            builder: EasyLoading.init(),
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            home: Scaffold(
                body: Column(children: [
              GroupLiveWatchSurface(
                  featureContext: featureContext,
                  session: liveSession(status: LiveStatus.live),
                  videoFactory: (uri) => TestLiveVideo(uri),
                  onClose: () {}),
            ])))));
    await frames(tester);
    addTearDown(() => _unmount(tester));
  }

  for (final dark in [false, true]) {
    testWidgets(
        'actual group watch opens the existing tip sheet (${dark ? 'dark' : 'light'})',
        (tester) async {
      await tester.runAsync(() => store.loadCapabilities('group#1'));
      await mount(tester, dark: dark);
      expect(find.byTooltip('打赏主播'), findsOneWidget);
      await tester.tap(find.byTooltip('打赏主播'));
      await frames(tester);
      expect(find.text('打赏主播'), findsOneWidget);
      expect(find.text('99BI'), findsWidgets);
      expect(find.text('确认打赏'), findsOneWidget);
      expect(tipped, false); // Entry alone never submits or deducts.
      expect(transport.requests.where((r) => r.path.endsWith('/tip')), isEmpty);
      await _unmount(tester);
      await frames(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'confirmed LIVE allows tipping while the same SDK mirror is ready',
      (tester) async {
    store.apply('group#1', _features(2, status: 'ready'));
    await tester.runAsync(() => store.loadCapabilities('group#1'));
    await mount(tester);
    expect(find.byTooltip('打赏主播'), findsOneWidget);
    await tester.tap(find.byTooltip('打赏主播'));
    await frames(tester);
    expect(find.text('确认打赏'), findsOneWidget);
    expect(tipped, false);
    await _unmount(tester);
    await frames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fullscreen tip entry checks the latest accepted group summary',
      (tester) async {
    await tester.runAsync(() => store.loadCapabilities('group#1'));
    await mount(tester);
    await tester.tap(find.text('全屏观看'));
    await frames(tester);
    expect(find.byTooltip('打赏主播').hitTestable(), findsOneWidget);
    store.seed(GroupInfo(
        groupID: 'group#1',
        ex: jsonEncode({'groupFeatures': _features(2, status: 'ended')})));
    await frames(tester);
    expect(find.byTooltip('打赏主播').hitTestable(), findsNothing);
    expect(find.text('打赏主播'), findsNothing);
    expect(tipped, false);
    await _unmount(tester);
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
}
