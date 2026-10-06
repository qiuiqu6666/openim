import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/live/group_live_module.dart';
import 'package:openim/pages/group_features/live/pages/live_manage_page.dart';
import 'package:openim/pages/group_features/live/pages/live_push_page.dart';
import 'package:openim/pages/group_features/live/pages/live_tip_sheet.dart';
import 'package:openim/pages/group_features/live/playback/live_playback_controller.dart';
import 'package:openim/pages/group_features/live/playback/live_player_view.dart';
import 'package:openim/pages/group_features/live/playback/live_watch_state.dart';
import 'package:openim/pages/group_features/live/widgets/live_banner.dart';
import 'package:openim/pages/group_features/live/widgets/live_style.dart';
import 'package:openim/pages/group_features/live/widgets/live_watch_surface.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim/services/fund_pending_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:video_player/video_player.dart';
import 'live_test_support.dart';

const _previewOutput = String.fromEnvironment('GROUP_LIVE_PREVIEW');
bool _fonts = false;

class _PaymentSecurity extends StubSettingsService {
  @override
  Future<bool> hasTradePassword() async => true;
}

Future<void> _mount(WidgetTester tester, Widget child,
    {bool dark = false,
    double scale = 1,
    Size size = const Size(375, 812),
    GlobalKey? key}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  configureEasyLoadingInteractions();
  Styles.isDark = dark;
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              fontFamily: _fonts ? 'LivePreview' : null,
              scaffoldBackgroundColor: AppTokens.background(dark: dark)),
          builder: EasyLoading.init(
              builder: (context, body) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: body!)),
          home: RepaintBoundary(key: key, child: child))));
  await tester.pump();
  addTearDown(() => _unmount(tester));
}

Future<void> _unmount(WidgetTester tester) async {
  await EasyLoading.dismiss(animation: false);
  await tester.pump();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> _assets(WidgetTester tester, BuildContext context) async {
  await tester.runAsync(() async {
    for (final asset in [
      LiveStyle.backgroundAsset,
      LiveStyle.createAsset,
      LiveStyle.onlineAsset,
      LiveStyle.bannerAsset,
      LiveStyle.heroAsset
    ]) {
      await precacheImage(AssetImage(asset), context);
    }
  });
  await tester.pumpAndSettle();
}

// The underlying tip form intentionally remains locked with a spinner while the
// PIN sheet is open. Advancing a bounded number of frames must not wait for that
// animation to stop before the test can enter the PIN.
Future<void> _paymentFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 16; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<LiveWatchState> _playingState(List<TestLiveVideo> videos) async {
  final transport =
      LiveTransport((request) => request.path.endsWith('/play-info')
          ? {
              'liveSessionId': 'live-1',
              'roomName': '每日直播',
              'protocol': 'hls',
              'playUrl': 'https://video.test/1.m3u8'
            }
          : liveDTO(status: 'LIVE'));
  final state = LiveWatchState(
      liveContext(transport.api()), liveSession(status: LiveStatus.live),
      videoFactory: (source) {
    final video = TestLiveVideo(source);
    videos.add(video);
    return video;
  });
  await state.load();
  // The owner starts its decoder without awaiting it. Complete that async work
  // in the same real zone before returning to the widget test's fake clock.
  await Future<void>.delayed(Duration.zero);
  expect(state.playback?.ready, isTrue);
  return state;
}

Widget _playingHost(LiveWatchState state) => Scaffold(
    body: AnimatedBuilder(
        animation: state,
        builder: (_, __) => state.playback == null
            ? const Center(child: Text('直播已结束'))
            : AspectRatio(
                aspectRatio: 16 / 9,
                child: LivePlayerView(controller: state.playback!))));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.testMode = true);
  tearDown(() {
    Get.reset();
    Styles.isDark = false;
  });
  for (final dark in [false, true]) {
    testWidgets(
        'actual banner keeps reference geometry and opens 16:9 waiting surface (${dark ? 'dark' : 'light'})',
        (tester) async {
      final transport = LiveTransport((request) =>
          request.path.endsWith('/current')
              ? {'active': true, 'session': liveDTO()}
              : liveDTO());
      final features = GroupFeatures.fromJson({
        'schemaVersion': 1,
        'revision': 1,
        'live': {
          'status': 'ready',
          'sessionID': 'live-1',
          'roomName': '每日直播',
          'description': '和大家边看边聊'
        }
      });
      await _mount(
          tester,
          Scaffold(
              body: GroupLiveFeatureHost(
                  featureContext:
                      liveContext(transport.api(), features: features))),
          dark: dark);
      await _assets(tester, tester.element(find.byType(GroupLiveBanner)));
      expect(tester.getSize(find.byType(GroupLiveBanner)).height, 56);
      expect(transport.requests.length, 1);
      expect(transport.requests.single.path, endsWith('/current'));
      // Entry calibrates public state without fetching media credentials.
      await tester.tap(find.text('进入直播间'));
      await tester.pumpAndSettle();
      final surface = find.byType(GroupLiveWatchSurface);
      expect(tester.getSize(surface).aspectRatio, closeTo(16 / 9, .01));
      expect(find.text('直播准备中，请稍候…'), findsOneWidget);
      expect(transport.requests.length, 2);
      expect(transport.requests.last.path, endsWith('/live/live-1'));
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(GroupLiveBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
    testWidgets(
        'scheduled push page never fetches credentials and handles large text (${dark ? 'dark' : 'light'})',
        (tester) async {
      final transport = LiveTransport((_) => liveDTO(status: 'SCHEDULED'));
      await _mount(
          tester,
          LivePushPage(
              featureContext: liveContext(transport.api()),
              session: liveSession(status: LiveStatus.scheduled)),
          dark: dark,
          scale: 1.5,
          size: const Size(320, 740));
      await _assets(tester, tester.element(find.byType(LivePushPage)));
      expect(find.text('直播已预约'), findsOneWidget);
      expect(transport.requests.length, 1);
      expect(find.text('推流地址'), findsNothing);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }
  testWidgets(
      'failed current request shows retry instead of a pretend setup success',
      (tester) async {
    final transport = LiveTransport((_) => {})..status = 404;
    await _mount(
        tester, LiveManagePage(featureContext: liveContext(transport.api())));
    await tester.pumpAndSettle();
    expect(find.text('该功能的服务暂未开通'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-room-name')), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(transport.requests.length, 2);
    expect(find.text('直播设置已保存'), findsNothing);
    await _unmount(tester);
  });
  testWidgets('create form uses reference limits and inline counters',
      (tester) async {
    final transport = LiveTransport((_) => {'active': false});
    await _mount(
        tester, LiveManagePage(featureContext: liveContext(transport.api())));
    await _assets(tester, tester.element(find.byType(LiveManagePage)));
    final name = find.byKey(const ValueKey('live-room-name'));
    final description = find.byType(TextField).last;
    expect(tester.widget<TextField>(name).maxLength, 10);
    expect(tester.widget<TextField>(description).maxLength, 30);
    await tester.ensureVisible(name);
    await tester.enterText(name, '123456789012');
    await tester.pump();
    expect(tester.widget<TextField>(name).controller!.text, '1234567890');
    expect(find.text('10/10'), findsOneWidget);
    final counter = find.text('10/10');
    expect(
        tester.getCenter(counter).dx, greaterThan(tester.getCenter(name).dx));
    expect(tester.getCenter(counter).dy, closeTo(tester.getCenter(name).dy, 2));
    await tester.ensureVisible(description);
    await tester.enterText(description, '1234567890123456789012345678901234');
    await tester.pump();
    expect(tester.widget<TextField>(description).controller!.text.length, 30);
    expect(find.text('30/30'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });
  testWidgets(
      'private permission invalidation removes a previously visible push key',
      (tester) async {
    var allowed = true;
    final events = StreamController<Map<String, dynamic>>.broadcast();
    final transport = LiveTransport((request) =>
        request.path.endsWith('/push-info')
            ? {
                'rtmpServer': 'rtmp://push.example.test/live',
                'streamKey': 'private-key'
              }
            : liveDTO());
    await _mount(
        tester,
        LivePushPage(
            featureContext: liveContext(transport.api(),
                capabilitiesCurrent: () => allowed, events: events.stream),
            session: liveSession()));
    await _assets(tester, tester.element(find.byType(LivePushPage)));
    expect(
        find.text('rtmp://push.example.test/live/private-key'), findsOneWidget);
    allowed = false;
    events.add({'key': 'groupFeatureCapabilitiesChanged', 'action': 'changed'});
    await tester.pumpAndSettle();
    expect(
        find.text('rtmp://push.example.test/live/private-key'), findsNothing);
    expect(find.text('操作权限已变化，请重新打开页面'), findsOneWidget);
    expect(transport.requests.length, 2);
    await _unmount(tester);
    await events.close();
  });
  testWidgets(
      'ended shared session closes its fullscreen route with one native player',
      (tester) async {
    final videos = <TestLiveVideo>[];
    final state = (await tester.runAsync(() => _playingState(videos)))!;
    addTearDown(() {
      if (state.current) state.dispose();
    });
    await _mount(tester, _playingHost(state));
    await tester.pumpAndSettle();
    final controller = state.playback!;
    // A second room lease must not keep an ended session's decoder alive.
    final roomLease =
        LivePlaybackOwner.acquire('self', controller.info, () => true);
    addTearDown(() => LivePlaybackOwner.release(roomLease));
    expect(identical(controller, roomLease), isTrue);
    await tester.tap(find.text('全屏观看'));
    await tester.pumpAndSettle();
    expect(find.text('退出全屏'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(videos.length, 1);
    expect(videos.single.plays, 1);
    state.acceptSession(liveSession(status: LiveStatus.ended, version: 2));
    await tester.pumpAndSettle();
    expect(find.text('退出全屏'), findsNothing);
    expect(find.text('直播已结束'), findsOneWidget);
    expect(Navigator.of(tester.element(find.text('直播已结束'))).canPop(), isFalse);
    expect(videos.length, 1);
    expect(videos.single.closes, 1);
    expect(roomLease.current, isFalse);
    expect(tester.takeException(), isNull);
    LivePlaybackOwner.release(roomLease);
    await _unmount(tester);
    state.dispose();
  });
  for (final switched in [false, true]) {
    testWidgets(
        'SDK-only ${switched ? 'new session' : 'end'} clears frozen push credentials',
        (tester) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      final transport = LiveTransport((request) =>
          request.path.endsWith('/push-info')
              ? {
                  'rtmpServer': 'rtmp://push.test/live',
                  'streamKey': 'old-private-key'
                }
              : liveDTO(status: 'LIVE'));
      await _mount(
          tester,
          LivePushPage(
              featureContext:
                  liveContext(transport.api(), events: events.stream),
              session: liveSession(status: LiveStatus.live)));
      await _assets(tester, tester.element(find.byType(LivePushPage)));
      expect(
          find.text('rtmp://push.test/live/old-private-key'), findsOneWidget);
      events.add({
        'key': 'groupFeaturesChanged',
        'groupID': 'group#1',
        'data': {
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 100,
            'live': {
              'sessionID': switched ? 'live-2' : 'live-1',
              'status': switched ? 'live' : 'ended'
            }
          }
        }
      });
      await tester.pump();
      await tester.pump(); // Async broadcast arrives after the first frame.
      expect(find.text('rtmp://push.test/live/old-private-key'), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.textContaining(switched ? '场次已变化' : '直播已结束'), findsOneWidget);
      expect(find.text('rtmp://push.test/live/old-private-key'), findsNothing);
      expect(
          transport.requests.where((r) => r.path.endsWith('/push-info')).length,
          1);
      // A definitive SDK end/session replacement needs no old-scene read.
      expect(transport.requests.length, 2);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
      await events.close();
    });
    testWidgets(
        'SDK-only ${switched ? 'new session' : 'end'} reaches the frozen watch surface',
        (tester) async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      final transport = LiveTransport((_) => liveDTO());
      await _mount(
          tester,
          Scaffold(
              body: GroupLiveWatchSurface(
                  featureContext:
                      liveContext(transport.api(), events: events.stream),
                  session: liveSession(),
                  onClose: () {})));
      await tester.pumpAndSettle();
      expect(find.text('直播准备中，请稍候…'), findsOneWidget);
      events.add({
        'key': 'groupFeaturesChanged',
        'groupID': 'group#1',
        'data': {
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 100,
            'live': {
              'sessionID': switched ? 'live-2' : 'live-1',
              'status': switched ? 'live' : 'ended'
            }
          }
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.textContaining(switched ? '场次已变化' : '直播已结束'), findsOneWidget);
      // The accepted SDK summary already closes this frozen scene.
      expect(transport.requests.length, 1);
      expect(find.byType(VideoPlayer), findsNothing);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
      await events.close();
    });
  }
  testWidgets(
      'ended fullscreen removes only its own route after the inline owner disappears',
      (tester) async {
    final videos = <TestLiveVideo>[];
    final state = (await tester.runAsync(() => _playingState(videos)))!;
    addTearDown(() {
      if (state.current) state.dispose();
    });
    await _mount(tester, _playingHost(state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全屏观看'));
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.text('退出全屏')));
    unawaited(navigator.push<void>(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('其他页面'))))));
    await tester.pumpAndSettle();
    state.acceptSession(liveSession(status: LiveStatus.ended, version: 2));
    await tester.pumpAndSettle();
    expect(find.text('其他页面'), findsOneWidget);
    expect(find.text('退出全屏', skipOffstage: false), findsNothing);
    expect(videos.length, 1);
    expect(videos.single.closes, 1);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('直播已结束'), findsOneWidget);
    expect(navigator.canPop(), isFalse);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
    state.dispose();
  });
  testWidgets(
      'uncertain tip survives closing and reopening with the same real payment request',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var fail = true;
    final transport = LiveTransport((request) {
      if (fail) {
        throw DioException(
            requestOptions: request, type: DioExceptionType.connectionError);
      }
      return {'tipId': 42, 'liveSessionId': 'live-1'};
    });
    final fixture = liveContext(transport.api());
    final store = FundPendingStore(accountKey: 'https://example.test:self');
    await _mount(
        tester,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => GroupLiveTipSheet.show(context,
                        featureContext: fixture,
                        session: liveSession(status: LiveStatus.live),
                        security: _PaymentSecurity(),
                        pendingStore: store),
                    child: const Text('打开打赏')))));
    await tester.tap(find.text('打开打赏'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1.000001');
    await tester.enterText(find.byType(TextField).last, '谢谢');
    await tester.tap(find.text('确认打赏'));
    await _paymentFrames(tester);
    expect(find.byKey(const ValueKey('trade-password-key-1')), findsOneWidget);
    for (final digit in '123456'.split('')) {
      await tester.tap(find.byKey(ValueKey('trade-password-key-$digit')));
      await tester.pump();
    }
    await _paymentFrames(tester);
    expect(transport.requests.length, 1);
    expect(find.text('操作结果尚未确认，请刷新后查看'), findsWidgets);
    final firstRequest =
        Map<String, dynamic>.from(transport.requests.single.data as Map);
    expect(firstRequest['amount'], 1000001);
    await tester.tap(find.byKey(const ValueKey('payment-cancel')));
    await _paymentFrames(tester);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开打赏'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse);
    expect(find.text('重试原交易'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重试原交易'));
    await _paymentFrames(tester);
    expect(find.byKey(const ValueKey('trade-password-key-1')), findsOneWidget);
    for (final digit in '123456'.split('')) {
      await tester.tap(find.byKey(ValueKey('trade-password-key-$digit')));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));
    await _paymentFrames(tester);
    expect(transport.requests.length, 2);
    expect(transport.requests.last.data, firstRequest);
    expect(await store.read('group-live-tip:group#1:live-1'), isNull);
    expect(find.text('打开打赏'), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-sheet')), findsNothing);
    await _unmount(tester);
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgets(
      'review live create, push and waiting surfaces with reference art in light/dark',
      (tester) async {
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = oldShadows);
    await tester.runAsync(() async {
      final file = File('C:/Windows/Fonts/msyh.ttc');
      if (await file.exists()) {
        await (FontLoader('LivePreview')
              ..addFont(file.readAsBytes().then(ByteData.sublistView)))
            .load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
        _fonts = true;
      }
    });
    for (final dark in [false, true]) {
      for (final page in ['create', 'push', 'waiting']) {
        final transport =
            LiveTransport((request) => request.path.endsWith('/current')
                ? {'active': false}
                : request.path.endsWith('/push-info')
                    ? {
                        'rtmpServer': 'rtmp://push.example.test/live',
                        'streamKey': 'stream-key',
                        'obsHint': '请分别复制地址和密钥到 OBS。'
                      }
                    : liveDTO());
        final fixture = liveContext(transport.api());
        final child = page == 'create'
            ? LiveManagePage(featureContext: fixture)
            : page == 'push'
                ? LivePushPage(featureContext: fixture, session: liveSession())
                : Scaffold(
                    body: Column(children: [
                    GroupLiveBanner(session: liveSession(), onWatch: () {}),
                    const SizedBox(height: 12),
                    GroupLiveWatchSurface(
                        featureContext: fixture,
                        session: liveSession(),
                        onClose: () {})
                  ]));
        final key = GlobalKey();
        await _mount(tester, child, dark: dark, key: key);
        await _assets(tester, key.currentContext!);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file =
              File('$_previewOutput-$page-${dark ? 'dark' : 'light'}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      }
    }
    debugDisableShadows = oldShadows;
  }, skip: _previewOutput.isEmpty);
}
