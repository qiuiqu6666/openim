import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/live/widgets/live_banner.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/widgets/group_chat_feature_surface.dart';
import 'package:openim_common/openim_common.dart';
import '../../support/account_privilege_fixture.dart';

const _summary = {
  'schemaVersion': 1,
  'revision': 2,
  'live': {
    'status': 'ready',
    'sessionID': 'live-1',
    'roomName': '群直播',
    'description': '欢迎进入直播间'
  },
  'games': {
    'sangong': {'enabled': true, 'manageEntry': true, 'agentEntry': true},
    'markSix': {
      'enabled': true,
      'agentEntry': true,
      'drawHistoryEntry': true,
      'rebateHistoryEntry': true,
      'machineCode': 'group-machine'
    }
  }
};
const _caps = {
  'groupID': 'g',
  'capabilityVersion': 1,
  'live': {'canConfigure': true, 'canManage': true},
  'sangong': {
    'canManage': true,
    'canOpenAgent': true,
    'tenantID': 'confirmed-tenant'
  },
  'markSix': {'canOpenAgent': true, 'canViewRebateHistory': true}
};

class _FixtureHTTP implements HttpClientAdapter {
  final streams = <StreamController<Uint8List>>[];
  final requests = <String>[];
  @override
  Future<ResponseBody> fetch(RequestOptions request, Stream<Uint8List>? body,
      Future<void>? cancelled) async {
    requests.add(request.path);
    if (request.path.endsWith('/events/stream')) {
      final stream = StreamController<Uint8List>();
      streams.add(stream);
      cancelled?.then((_) {
        if (!stream.isClosed) stream.close();
      });
      return ResponseBody(stream.stream, 200, headers: {
        Headers.contentTypeHeader: ['text/event-stream']
      });
    }
    final Object data = request.path.endsWith('/feature-capabilities')
        ? _caps
        : request.path.endsWith('/admin/tenants/g')
            ? {'tenantId': 'g', 'imGroupGameId': 'g', 'active': true}
            : request.path.endsWith('/events/snapshot')
                ? {
                    'version': 1,
                    'status': 'running',
                    'settings': {'doorCount': 6},
                    'round': {
                      'id': 1,
                      'issueNo': 1,
                      'bankerNickname': '小林',
                      'bankerDoor': 3,
                      'bankerLimit': 10000,
                      'betWindowOpenedAt': '2026-10-04T10:00:00Z'
                    },
                    'pending': {
                      'open': true,
                      'grandTotal': 1200,
                      'doorTotals': {
                        '1': 200,
                        '2': 100,
                        '3': 300,
                        '4': 200,
                        '5': 200,
                        '6': 200
                      }
                    }
                  }
                : <String, dynamic>{};
    return ResponseBody.fromString(
        jsonEncode({'errCode': 0, 'data': data}), 200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {
    for (final stream in streams) {
      if (!stream.isClosed) stream.close();
    }
  }
}

Future<void> _fonts() async {
  final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
  await (FontLoader('GroupFeaturePreview')..addFont(Future.value(bytes)))
      .load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
  await (FontLoader('packages/cupertino_icons/CupertinoIcons')
        ..addFont(rootBundle
            .load('packages/cupertino_icons/assets/CupertinoIcons.ttf')))
      .load();
}

void _expectFlushLiveBanner(WidgetTester tester) {
  final banner = find.byType(GroupLiveBanner);
  final bannerRect = tester.getRect(banner);
  final navigationRect = tester.getRect(find.byType(AppBar));
  final surfaceRect = tester.getRect(find.byType(GroupChatFeatureSurface));
  expect(bannerRect.top, closeTo(navigationRect.bottom, .01));
  expect(bannerRect.left, closeTo(surfaceRect.left, .01));
  expect(bannerRect.right, closeTo(surfaceRect.right, .01));
  expect(bannerRect.height, 56);
  final material = tester.widget<Material>(
      find.descendant(of: banner, matching: find.byType(Material)).first);
  expect(material.borderRadius ?? BorderRadius.zero, BorderRadius.zero);
  expect(material.shape, isNull);
  final inkWell = tester.widget<InkWell>(
      find.descendant(of: banner, matching: find.byType(InkWell)).first);
  expect(inkWell.borderRadius ?? BorderRadius.zero, BorderRadius.zero);
}

void main() {
  final export = Platform.environment['EXPORT_GROUP_FEATURE_PREVIEW'] == '1';
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final dark in [false, true]) {
      testWidgets(
          'combined live and two games remain bounded and let chat receive taps $platform dark=$dark',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        if (export) await tester.runAsync(_fonts);
        final oldShadows = debugDisableShadows;
        if (export) {
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = oldShadows);
        }
        try {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          Styles.isDark = dark;
          addTearDown(() => Styles.isDark = false);
          final adapter = _FixtureHTTP();
          final api = GroupFeatureApi(
              client: Dio()..httpClientAdapter = adapter,
              baseUrl: 'https://fixture.example',
              tokenProvider: () => 'chat',
              userProvider: () => 'me');
          final store = GroupFeatureStore(
              accountPrivilege: FixtureAccountPrivilege(),
              api: api,
              sessionCurrent: () => true,
              fetchGroups: (_) async => []);
          final feature = GroupFeatureContext(
              gameType: GroupGameType.sangong,
              accountPrivilege: store.accountPrivilege,
              groupID: 'g',
              groupName: '群聊',
              currentUserID: 'me',
              api: api,
              features: GroupFeatures.fromJson(_summary),
              capabilities: GroupFeatureCapabilities.fromJson(_caps),
              isGroupAdmin: true,
              sessionCurrent: () => true,
              onFeaturesChanged: (_) {},
              events: store.events('g'));
          final key = GlobalKey();
          var taps = 0;
          await tester.pumpWidget(ScreenUtilInit(
              designSize: const Size(375, 812),
              builder: (_, __) => MaterialApp(
                  locale: const Locale('zh', 'CN'),
                  supportedLocales: const [Locale('zh', 'CN')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: ThemeData(
                      fontFamily: export ? 'GroupFeaturePreview' : null,
                      platform: platform,
                      scaffoldBackgroundColor: AppTokens.background(dark: dark),
                      colorScheme: ColorScheme.fromSeed(
                          seedColor: const Color(0xFF0089FF),
                          brightness:
                              dark ? Brightness.dark : Brightness.light),
                      appBarTheme: AppBarTheme(
                          backgroundColor: AppTokens.surface(dark: dark),
                          surfaceTintColor: Colors.transparent),
                      brightness: dark ? Brightness.dark : Brightness.light),
                  home: RepaintBoundary(
                      key: key,
                      child: Scaffold(
                          appBar: AppBar(title: const Text('群聊')),
                          body: GroupChatFeatureSurface(
                              store: store,
                              featureContext: feature,
                              child: Column(children: [
                                Expanded(
                                    child: Center(
                                        child: TextButton(
                                            key: const ValueKey(
                                                'chat-tap-target'),
                                            onPressed: () => taps++,
                                            child: const Text('聊天消息')))),
                                Container(
                                    height: 52,
                                    color: dark
                                        ? AppTokens.surfaceDark
                                        : Colors.white,
                                    child: const Row(children: [
                                      SizedBox(width: 12),
                                      Icon(Icons.keyboard_voice_outlined),
                                      SizedBox(width: 12),
                                      Expanded(child: Text('输入消息')),
                                      Icon(Icons.add_circle_outline),
                                      SizedBox(width: 12)
                                    ]))
                              ])))))));
          await tester.pumpAndSettle();
          expect(find.text('群直播'), findsOneWidget);
          _expectFlushLiveBanner(tester);
          expect(find.byKey(const ValueKey('lottery-edge-handle')),
              findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('chat-tap-target')));
          await tester.pump();
          expect(taps, 1);
          expect(tester.takeException(), isNull);
          expect(
              adapter.requests
                  .where((path) => path.endsWith('/events/snapshot'))
                  .length,
              1);
          expect(
              adapter.requests
                  .where((path) => path.endsWith('/events/stream'))
                  .length,
              1);
          if (export) {
            await tester.runAsync(() => precacheImage(
                const AssetImage('assets/img/group_live_banner.webp'),
                key.currentContext!));
            await tester.pump();
            final boundary = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final screenshot = await boundary.toImage(pixelRatio: 2);
              final png =
                  await screenshot.toByteData(format: ui.ImageByteFormat.png);
              final file = File(
                  'docs/previews/group-features/chat-${platform.name}-${dark ? 'dark' : 'light'}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png!.buffer.asUint8List());
              screenshot.dispose();
            });
          }
          tester.view.physicalSize = const Size(320, 360);
          await tester.pumpAndSettle();
          _expectFlushLiveBanner(tester);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          store.dispose();
          adapter.close();
        } finally {
          if (export) debugDisableShadows = oldShadows;
        }
      });
    }
  }
}
