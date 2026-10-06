import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/widgets/live_watch_surface.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim_common/openim_common.dart';

import 'live_test_support.dart';

LiveSession _summary({LiveStatus status = LiveStatus.authorized}) =>
    LiveSession(
      id: 'live-1',
      groupID: 'group#1',
      status: status,
      roomName: '每日直播',
      description: '和大家边看边聊',
      anchorID: 'anchor',
    );

/// Rebuilds only the parent. Its empty event stream deliberately excludes the
/// separate SDK summary debounce from these session-input regression checks.
class _SurfaceFixture {
  _SurfaceFixture(this.transport, {LiveSession? session})
      : session = session ?? liveSession() {
    context = liveContext(transport.api());
  }

  final LiveTransport transport;
  late final GroupFeatureContext context;
  final generation = ValueNotifier(0);
  final reported = <LiveSession>[];
  LiveSession session;

  int get detailReads => transport.requests
      .where((request) => request.path.endsWith('/live/live-1'))
      .length;

  void rebuild({LiveSession? session}) {
    this.session = session ?? this.session;
    generation.value++;
  }

  void dispose() => generation.dispose();
}

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _mount(WidgetTester tester, _SurfaceFixture fixture) async {
  tester.view.physicalSize = const Size(390, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(fixture.dispose);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: fixture.generation,
          builder: (_, __, ___) => Column(children: [
            GroupLiveWatchSurface(
              featureContext: fixture.context,
              session: fixture.session,
              onClose: () {},
              onStateChanged: fixture.reported.add,
            ),
          ]),
        ),
      ),
    ),
  ));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await _frames(tester);
}

Finder get _spinner => find.descendant(
      of: find.byType(GroupLiveWatchSurface),
      matching: find.byType(CircularProgressIndicator),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.testMode = true);
  tearDown(() {
    Get.reset();
    Styles.isDark = false;
  });

  testWidgets('same-status summary cannot restart a calibrated waiting surface',
      (tester) async {
    final repeated = Completer<Map<String, dynamic>>();
    addTearDown(() {
      if (!repeated.isCompleted) repeated.complete(liveDTO());
    });
    var reads = 0;
    final fixture = _SurfaceFixture(LiveTransport((_) {
      if (++reads == 1) return liveDTO();
      return repeated.future;
    }));
    await _mount(tester, fixture);
    expect(fixture.detailReads, 1);
    expect(_spinner, findsNothing);

    fixture.rebuild(session: _summary());
    await _frames(tester);
    expect(fixture.detailReads, 1);
    expect(_spinner, findsNothing);

    for (var rebuild = 0; rebuild < 3; rebuild++) {
      fixture.rebuild(session: _summary());
      await _frames(tester);
    }
    expect(fixture.detailReads, 1);
    expect(_spinner, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged initial summary does not reload after detail resolves',
      (tester) async {
    final fixture = _SurfaceFixture(
      LiveTransport((_) => liveDTO()),
      session: _summary(),
    );
    await _mount(tester, fixture);
    expect(fixture.reported.single.version, 1);
    expect(fixture.detailReads, 1);

    fixture.rebuild();
    await _frames(tester);
    expect(fixture.detailReads, 1);
    expect(_spinner, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('different-status version-zero summary still calibrates detail',
      (tester) async {
    final calibrated = Completer<Map<String, dynamic>>();
    addTearDown(() {
      if (!calibrated.isCompleted) {
        calibrated.complete(liveDTO(status: 'SCHEDULED', version: 2));
      }
    });
    var reads = 0;
    final fixture = _SurfaceFixture(LiveTransport((_) {
      if (++reads == 1) return liveDTO();
      return calibrated.future;
    }));
    await _mount(tester, fixture);

    fixture.rebuild(session: _summary(status: LiveStatus.scheduled));
    await _frames(tester);
    expect(fixture.detailReads, 2);
    expect(_spinner, findsOneWidget);
    calibrated.complete(liveDTO(status: 'SCHEDULED', version: 2));
    await _frames(tester);
    expect(find.text('直播尚未开始，请稍候'), findsOneWidget);
    expect(fixture.reported.last.version, 2);
    expect(fixture.reported.last.status, LiveStatus.scheduled);

    fixture.rebuild();
    await _frames(tester);
    expect(fixture.detailReads, 2);
    expect(_spinner, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('newer detailed session still refreshes exactly once',
      (tester) async {
    final refreshed = Completer<Map<String, dynamic>>();
    addTearDown(() {
      if (!refreshed.isCompleted) refreshed.complete(liveDTO(version: 2));
    });
    var reads = 0;
    final fixture = _SurfaceFixture(LiveTransport((_) {
      if (++reads == 1) return liveDTO();
      return refreshed.future;
    }));
    await _mount(tester, fixture);

    fixture.rebuild(session: liveSession(version: 2));
    await _frames(tester);
    expect(fixture.detailReads, 2);
    expect(_spinner, findsOneWidget);
    refreshed.complete(liveDTO(version: 2));
    await _frames(tester);
    expect(_spinner, findsNothing);

    fixture.rebuild();
    await _frames(tester);
    expect(fixture.detailReads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a calibrated status disagreement does not repeat on rebuild',
      (tester) async {
    final fixture = _SurfaceFixture(LiveTransport((_) => liveDTO()));
    await _mount(tester, fixture);

    // A newer group revision may carry a status downgrade. Verify it against
    // detail once, then keep the authoritative session while that same input
    // remains on screen. Group revisions are not scene DTO versions.
    fixture.rebuild(session: _summary(status: LiveStatus.scheduled));
    await _frames(tester);
    expect(fixture.detailReads, 2);
    expect(find.text('直播准备中，请稍候…'), findsOneWidget);
    for (var rebuild = 0; rebuild < 3; rebuild++) {
      fixture.rebuild();
      await _frames(tester);
    }
    expect(fixture.detailReads, 2);
    expect(_spinner, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
