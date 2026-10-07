import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/sangong_module.dart';
import 'package:openim/pages/group_features/sangong/widgets/group_game_floating_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sangong_test_support.dart';

const _previewOutput = String.fromEnvironment('SANGONG_STATUS_PREVIEW');
const _size = Size(390, 844);
const _initialLine = '庄【】包共0注';
const _retryKey = ValueKey('sangong-host-retry');

// The service's initial complete snapshot has an explicit zero for every door.
Map<String, dynamic> _idleState() => {
      'version': 0,
      'status': 'idle',
      'settings': {'doorCount': 6},
      'round': null,
      'pending': {
        'open': false,
        'messageCount': 0,
        'doorTotals': {for (var door = 1; door <= 6; door++) '$door': 0},
        'grandTotal': 0,
      },
      'placed': {
        'betCount': 0,
        'doorTotals': {for (var door = 1; door <= 6; door++) '$door': 0},
        'grandTotal': 0,
      },
    };

Map<String, dynamic> _invalidState(String kind) {
  final state = _idleState();
  switch (kind) {
    case 'missing version':
      state.remove('version');
      break;
    case 'negative version':
      state['version'] = -1;
      break;
    case 'missing settings':
      state.remove('settings');
      break;
  }
  return state;
}

class _Fixture {
  _Fixture() {
    api.respond = (call) {
      if (call.path.endsWith('/events/snapshot')) return _snapshot();
      return sangongFixtureResponse(call);
    };
    context = sangongTestContext(api,
        groupID: '@status-group',
        tenantID: '@status-group',
        agentEntry: false,
        canOpenAgent: false,
        current: () => active);
  }

  final api = SangongTestApi();
  late final GroupFeatureContext context;
  SangongRuntime? runtime;
  FutureOr<Map<String, dynamic>> Function()? snapshotResponse;
  bool active = true;
  bool _disposed = false;

  Future<Map<String, dynamic>> _snapshot() async =>
      {'state': await (snapshotResponse?.call() ?? _idleState())};

  void emit(Map<String, dynamic> state, {bool split = false}) {
    final event = 'event: state\ndata: ${jsonEncode({'state': state})}\n\n';
    final stream = api.streams.single;
    if (split) {
      final midpoint = event.length ~/ 2;
      stream.add(event.substring(0, midpoint));
      stream.add(event.substring(midpoint));
    } else {
      stream.add(event);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    active = false;
    await api.closeStreams();
    api.privilege.dispose();
  }
}

Future<void> _pumpHost(WidgetTester tester, _Fixture fixture,
    {bool dark = false, GlobalKey? boundary, String? fontFamily}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await unmountSangong(tester);
    await fixture.dispose();
  });
  await tester.pumpWidget(ScreenUtilInit(
      designSize: _size,
      builder: (_, __) => MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              fontFamily: fontFamily),
          home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                  appBar: AppBar(
                      leading: BackButton(onPressed: () {}),
                      title: const Text('三公状态条测试'),
                      actions: const [
                        Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Icon(Icons.more_horiz))
                      ]),
                  body: SangongFeatureHost(
                      featureContext: fixture.context,
                      builder: (context, banner, overlay) {
                        fixture.runtime = SangongScope.read(context);
                        return Column(children: [
                          banner,
                          Expanded(
                              child: Stack(fit: StackFit.expand, children: [
                            const Center(child: Text('测试群聊消息区域')),
                            overlay,
                          ])),
                        ]);
                      }))))));
  await _flush(tester);
}

Future<void> _flush(WidgetTester tester) async {
  await flushSangong(tester);
  await tester.pump(const Duration(milliseconds: 350));
  await flushSangong(tester);
}

void _expectIdleBanner(WidgetTester tester, _Fixture fixture,
    {bool hasRealtimeError = false}) {
  final bannerFinder = find.byType(GroupGameStatusBanner);
  expect(bannerFinder, findsOneWidget);
  final banner = tester.widget<GroupGameStatusBanner>(bannerFinder);
  expect(banner.doorCount, 6);
  expect(banner.roundStatus.doorValuesForCount(6), [0, 0, 0, 0, 0, 0]);
  // This literal comes from the unmodified 99chat formatStatusLine contract.
  expect(banner.roundStatus.formatStatusLine(), _initialLine);
  expect(find.descendant(of: bannerFinder, matching: find.text(_initialLine)),
      findsOneWidget);
  expect(find.descendant(of: bannerFinder, matching: find.text('0')),
      findsNWidgets(6));
  for (var door = 1; door <= 6; door++) {
    expect(find.descendant(of: bannerFinder, matching: find.text('$door')),
        findsOneWidget);
  }
  expect(fixture.runtime!.realtime.latestState!.version, 0);
  expect(fixture.runtime!.realtime.latestState!.status, 'idle');
  expect(fixture.runtime!.realtime.latestState!.round, isNull);
  expect(
      fixture.runtime!.realtime.error, hasRealtimeError ? isNotNull : isNull);
  expect(find.byKey(_retryKey), findsNothing);
}

void _expectUpdatedBanner(WidgetTester tester, _Fixture fixture) {
  final banner =
      tester.widget<GroupGameStatusBanner>(find.byType(GroupGameStatusBanner));
  expect(banner.doorCount, 6);
  expect(banner.roundStatus.bankerName, '冬');
  expect(banner.roundStatus.bankerDoor, 1);
  expect(banner.roundStatus.doorValuesForCount(6), [0, 200, 100, 0, 0, 0]);
  expect(banner.roundStatus.totalBetCount, 300);
  expect(find.text('庄【冬】1包共300注 限制2000注'), findsOneWidget);
  expect(
      find.descendant(
          of: find.byType(GroupGameStatusBanner), matching: find.text('庄')),
      findsOneWidget);
  expect(fixture.runtime!.realtime.latestState!.version, 1);
  expect(fixture.runtime!.realtime.error, isNull);
  expect(find.byKey(_retryKey), findsNothing);
}

Future<void> _loadPreviewFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final path in [
      'C:/Windows/Fonts/msyh.ttf',
      'C:/Windows/Fonts/msyh.ttc'
    ]) {
      final font = File(path);
      if (!await font.exists()) continue;
      final bytes = ByteData.sublistView(await font.readAsBytes());
      await (FontLoader('SangongStatusPreviewFont')
            ..addFont(Future.value(bytes)))
          .load();
      await (FontLoader('Roboto')..addFont(Future.value(bytes))).load();
      break;
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OpenIM.iMManager.userID = 'owner';
  });

  for (final dark in [false, true]) {
    testWidgets(
        'HTTP version zero renders the original idle status, dark=$dark',
        (tester) async {
      final fixture = _Fixture();
      await _pumpHost(tester, fixture, dark: dark);
      _expectIdleBanner(tester, fixture);
      final snapshot = fixture.api.calls
          .singleWhere((call) => call.path.endsWith('/events/snapshot'));
      expect(snapshot.method, 'GET');
      expect(snapshot.useBearerAuth, isTrue);
      expect(fixture.api.streamStarts, 1);
      expect(fixture.runtime!.groupTenantReady, isTrue);
      expect(fixture.api.count('/my-config'), 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'SSE zero and then one render normally without HTTP zero rollback',
      (tester) async {
    final snapshotReply = Completer<Map<String, dynamic>>();
    final fixture = _Fixture()..snapshotResponse = () => snapshotReply.future;
    await _pumpHost(tester, fixture);
    expect(fixture.api.streamStarts, 1);
    expect(fixture.api.count('/events/snapshot'), 1);
    expect(fixture.runtime!.realtime.latestState, isNull);
    fixture.emit(_idleState(), split: true);
    await _flush(tester);
    _expectIdleBanner(tester, fixture);

    fixture.emit(sangongState(1), split: true);
    await _flush(tester);
    _expectUpdatedBanner(tester, fixture);
    snapshotReply.complete(_idleState());
    await _flush(tester);
    _expectUpdatedBanner(tester, fixture);

    // Even a newly requested stale HTTP snapshot cannot regress the stream.
    fixture.snapshotResponse = _idleState;
    await completeSangongRequest(
        tester, fixture.runtime!.realtime.refreshSnapshot());
    await _flush(tester);
    expect(fixture.api.count('/events/snapshot'), 2);
    _expectUpdatedBanner(tester, fixture);
    expect(fixture.api.streamStarts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a disconnected stream preserves the last valid blue status bar',
      (tester) async {
    final fixture = _Fixture();
    await _pumpHost(tester, fixture);
    _expectIdleBanner(tester, fixture);
    fixture.api.streams.single
        .addError(StateError('fixture stream disconnected'));
    await _flush(tester);
    _expectIdleBanner(tester, fixture, hasRealtimeError: true);
    expect(fixture.api.streamStarts, 1);
    expect(fixture.api.streamStops, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the saved hidden preference hides both the status and controls',
      (tester) async {
    final fixture = _Fixture();
    final preferenceKey =
        '${fixture.api.baseUrl}:${fixture.context.currentUserID}:${fixture.context.groupID}';
    SharedPreferences.setMockInitialValues({
      'group_game_float_visible_$preferenceKey': false,
    });
    await _pumpHost(tester, fixture);
    expect(fixture.runtime!.canManage, isTrue);
    expect(fixture.runtime!.realtime.latestState!.version, 0);
    expect(fixture.runtime!.realtime.error, isNull);
    expect(find.byType(GroupGameStatusBanner), findsNothing);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(find.byKey(_retryKey), findsNothing);
    expect(find.text('测试群聊消息区域'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final kind in [
    'missing version',
    'negative version',
    'missing settings'
  ]) {
    testWidgets(
        'HTTP $kind remains invalid instead of inventing an idle banner',
        (tester) async {
      final fixture = _Fixture()..snapshotResponse = () => _invalidState(kind);
      await _pumpHost(tester, fixture);
      expect(fixture.runtime!.realtime.latestState, isNull);
      expect(fixture.runtime!.realtime.error, isNotNull);
      expect(find.byType(GroupGameStatusBanner), findsNothing);
      expect(find.byKey(_retryKey), findsOneWidget);
      expect(fixture.api.count('/events/snapshot'), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'SSE $kind records an error without covering the accepted banner',
        (tester) async {
      final fixture = _Fixture();
      await _pumpHost(tester, fixture);
      _expectIdleBanner(tester, fixture);
      fixture.snapshotResponse = () => _invalidState(kind);
      fixture.emit(_invalidState(kind), split: true);
      await _flush(tester);
      _expectIdleBanner(tester, fixture, hasRealtimeError: true);
      expect(fixture.api.count('/events/snapshot'), 2);
      expect(fixture.api.streamStarts, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('export the actual idle Host under navigation in both themes',
      (tester) async {
    expect(File(_previewOutput).isAbsolute, isTrue);
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = oldShadows);
    await _loadPreviewFonts(tester);
    final captures = <ui.Image>[];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final fixture = _Fixture();
    final boundary = GlobalKey();
    var column = 0;
    for (final dark in [false, true]) {
      await _pumpHost(tester, fixture,
          dark: dark,
          boundary: boundary,
          fontFamily: 'SangongStatusPreviewFont');
      _expectIdleBanner(tester, fixture);
      expect(find.byType(AppBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final capture = (await tester.runAsync(() =>
          render.toImage(pixelRatio: 1).timeout(const Duration(seconds: 15))))!;
      captures.add(capture);
      canvas.drawImage(capture, Offset(column * _size.width, 0), Paint());
      column++;
    }
    final picture = recorder.endRecording();
    await tester.runAsync(() async {
      final image =
          await picture.toImage(780, 844).timeout(const Duration(seconds: 15));
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File(_previewOutput);
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      for (final capture in captures) {
        capture.dispose();
      }
    });
    debugDisableShadows = oldShadows;
  }, skip: _previewOutput.isEmpty);
}
