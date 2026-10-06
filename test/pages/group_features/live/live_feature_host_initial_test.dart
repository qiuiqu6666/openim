import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/live/group_live_module.dart';
import 'package:openim/pages/group_features/live/widgets/live_banner.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim_common/openim_common.dart';

import 'live_test_support.dart';

const _sdk = MethodChannel('flutter_openim_sdk');

Map<String, dynamic> _current({
  bool active = true,
  String id = 'live-1',
  String groupID = 'group#1',
  String status = 'AUTHORIZED',
  int version = 1,
}) =>
    {
      'active': active,
      if (active)
        'session': {
          ...liveDTO(id: id, status: status, version: version),
          'groupId': groupID,
        },
    };

GroupFeatures _features({
  String id = 'live-2',
  String status = 'live',
  int revision = 2,
}) =>
    GroupFeatures.fromJson({
      'schemaVersion': 1,
      'revision': revision,
      'live': {
        'sessionID': id,
        'status': status,
        'roomName': '新的群直播',
        'anchorUserID': 'anchor',
      },
      'games': {},
    });

/// Mirrors the account-owned context snapshots and event stream used by chat.
class _HostFixture {
  _HostFixture(this.transport) {
    api = transport.api();
    context = ValueNotifier(_snapshot());
  }

  final LiveTransport transport;
  late GroupFeatureApi api;
  late final ValueNotifier<GroupFeatureContext> context;
  final events = StreamController<Map<String, dynamic>>.broadcast();
  final changed = <LiveSession?>[];
  String groupID = 'group#1', userID = 'self';
  bool active = true;
  GroupFeatures features = const GroupFeatures();

  int get currentReads => transport.requests
      .where((request) => request.path.endsWith('/current'))
      .length;

  GroupFeatureContext _snapshot() {
    final capturedGroup = groupID, capturedUser = userID;
    final capturedApi = api;
    bool current() =>
        active &&
        groupID == capturedGroup &&
        userID == capturedUser &&
        identical(api, capturedApi);
    return GroupFeatureContext(
      groupID: capturedGroup,
      groupName: '直播群',
      currentUserID: capturedUser,
      api: capturedApi,
      features: features,
      sessionCurrent: current,
      onFeaturesChanged: (raw) {
        if (!current()) return;
        final next = GroupFeatures.fromJson(raw);
        if (next.valid && next.revision > features.revision) accept(next);
      },
      events: events.stream,
      readContext: _snapshot,
    );
  }

  void rebuild() => context.value = _snapshot();

  void accept(GroupFeatures next) {
    features = next;
    rebuild();
    events.add({
      'key': 'groupFeaturesChanged',
      'groupID': groupID,
      'data': {'groupFeatures': next.raw},
    });
  }

  void switchScope({String? group, String? user}) {
    groupID = group ?? groupID;
    userID = user ?? userID;
    features = const GroupFeatures();
    rebuild();
  }

  void switchRuntime() {
    api = transport.api();
    features = const GroupFeatures();
    rebuild();
  }

  Future<void> dispose() async {
    active = false;
    context.dispose();
    await events.close();
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _mount(
  WidgetTester tester,
  _HostFixture fixture, {
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(390, 812);
  tester.view.devicePixelRatio = 1;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = dark;
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        home: Scaffold(
          body: ValueListenableBuilder<GroupFeatureContext>(
            valueListenable: fixture.context,
            builder: (_, context, __) => GroupLiveFeatureHost(
              featureContext: context,
              onStateChanged: fixture.changed.add,
            ),
          ),
        ),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await _frames(tester);
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
      'chat discovers active live without SDK summary (${dark ? 'dark' : 'light'})',
      (tester) async {
        final fixture = _HostFixture(LiveTransport((_) => _current()));
        addTearDown(fixture.dispose);
        await _mount(tester, fixture, dark: dark);
        expect(find.byType(GroupLiveBanner), findsOneWidget);
        expect(find.text('每日直播'), findsOneWidget);
        expect(fixture.currentReads, 1);
        expect(fixture.changed.single?.id, 'live-1');
        expect(
          fixture.transport.requests.any(
            (request) =>
                request.path.endsWith('/play-info') ||
                request.path.endsWith('/push-info'),
          ),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('chat with no current live keeps its feature surface empty', (
    tester,
  ) async {
    final fixture = _HostFixture(
      LiveTransport((_) => _current(active: false)),
    );
    addTearDown(fixture.dispose);
    await _mount(tester, fixture);
    expect(find.byType(GroupLiveBanner), findsNothing);
    expect(fixture.currentReads, 1);
    expect(fixture.changed, [null]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('foreground refresh discovers a live started while away', (
    tester,
  ) async {
    var active = false;
    final fixture = _HostFixture(
      LiveTransport((_) => _current(active: active)),
    );
    addTearDown(fixture.dispose);
    await _mount(tester, fixture);
    expect(find.byType(GroupLiveBanner), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    active = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester);
    expect(fixture.currentReads, 2);
    expect(find.byType(GroupLiveBanner), findsOneWidget);
    expect(fixture.changed.last?.id, 'live-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('in-flight live changes coalesce into one follow-up current read',
      (
    tester,
  ) async {
    final reply = Completer<Map<String, dynamic>>();
    var reads = 0, inFlight = 0, maxInFlight = 0;
    final fixture = _HostFixture(LiveTransport((_) async {
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      try {
        if (++reads == 1) return await reply.future;
        return _current(id: 'live-2', status: 'LIVE', version: 2);
      } finally {
        inFlight--;
      }
    }));
    addTearDown(fixture.dispose);
    await _mount(tester, fixture);
    expect(fixture.currentReads, 1);
    fixture.rebuild();
    fixture.events.add({'key': 'liveSessionChanged', 'groupID': 'group#1'});
    fixture.events.add({'key': 'liveSessionChanged', 'groupID': 'group#1'});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester);
    expect(fixture.currentReads, 1);
    reply.complete(_current());
    await _frames(tester);
    expect(fixture.currentReads, 2);
    expect(maxInFlight, 1);
    expect(find.byType(GroupLiveBanner), findsOneWidget);
    expect(
      tester.widget<GroupLiveBanner>(find.byType(GroupLiveBanner)).session.id,
      'live-2',
    );
    expect(tester.takeException(), isNull);
  });

  for (final close in [true, false]) {
    testWidgets(
      'late initial response after ${close ? 'closing chat' : 'invalidating account'} is ignored',
      (tester) async {
        final reply = Completer<Map<String, dynamic>>();
        final fixture = _HostFixture(LiveTransport((_) => reply.future));
        addTearDown(fixture.dispose);
        await _mount(tester, fixture);
        expect(fixture.currentReads, 1);
        if (close) {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          fixture.active = false;
          fixture.rebuild();
          await tester.pump();
        }
        reply.complete(_current());
        await _frames(tester);
        expect(find.byType(GroupLiveBanner), findsNothing);
        expect(fixture.changed, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final groupSwitch in [true, false]) {
    testWidgets(
      'changing ${groupSwitch ? 'group' : 'account'} reads its new scope and ignores the old response',
      (tester) async {
        final oldReply = Completer<Map<String, dynamic>>();
        var requests = 0;
        final fixture = _HostFixture(
          LiveTransport((_) {
            if (++requests == 1) return oldReply.future;
            return _current(
              id: 'new-scope-live',
              groupID: groupSwitch ? 'group#2' : 'group#1',
            );
          }),
        );
        addTearDown(fixture.dispose);
        await _mount(tester, fixture);
        fixture.switchScope(
          group: groupSwitch ? 'group#2' : null,
          user: groupSwitch ? null : 'another-account',
        );
        await _frames(tester);
        expect(fixture.currentReads, 2);
        expect(
          tester
              .widget<GroupLiveBanner>(find.byType(GroupLiveBanner))
              .session
              .id,
          'new-scope-live',
        );
        oldReply.complete(_current());
        await _frames(tester);
        expect(
          tester
              .widget<GroupLiveBanner>(find.byType(GroupLiveBanner))
              .session
              .id,
          'new-scope-live',
        );
        expect(
            fixture.changed.map((session) => session?.id), ['new-scope-live']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
      'new account runtime with unchanged user and group fences old read', (
    tester,
  ) async {
    final oldReply = Completer<Map<String, dynamic>>();
    var reads = 0;
    final fixture = _HostFixture(LiveTransport((_) {
      if (++reads == 1) return oldReply.future;
      return _current(id: 'new-runtime-live');
    }));
    addTearDown(fixture.dispose);
    await _mount(tester, fixture);
    fixture.switchRuntime();
    await _frames(tester);
    expect(fixture.currentReads, 2);
    expect(
      tester.widget<GroupLiveBanner>(find.byType(GroupLiveBanner)).session.id,
      'new-runtime-live',
    );
    oldReply.complete(_current());
    await _frames(tester);
    expect(
      tester.widget<GroupLiveBanner>(find.byType(GroupLiveBanner)).session.id,
      'new-runtime-live',
    );
    expect(fixture.changed.map((session) => session?.id), ['new-runtime-live']);
    expect(tester.takeException(), isNull);
  });

  for (final newerEnded in [false, true]) {
    testWidgets(
      'newer SDK ${newerEnded ? 'end' : 'scene'} wins over a delayed initial current response',
      (tester) async {
        final reply = Completer<Map<String, dynamic>>();
        var reads = 0;
        final fixture = _HostFixture(LiveTransport((_) {
          if (++reads == 1) return reply.future;
          return _current(
            active: !newerEnded,
            id: 'live-2',
            status: 'LIVE',
            version: 2,
          );
        }));
        addTearDown(fixture.dispose);
        await _mount(tester, fixture);
        fixture.accept(_features(status: newerEnded ? 'ended' : 'live'));
        await _frames(tester);
        if (newerEnded) {
          expect(find.byType(GroupLiveBanner), findsNothing);
        } else {
          expect(
            tester
                .widget<GroupLiveBanner>(find.byType(GroupLiveBanner))
                .session
                .id,
            'live-2',
          );
        }
        reply.complete(_current());
        await _frames(tester);
        if (newerEnded) {
          expect(find.byType(GroupLiveBanner), findsNothing);
        } else {
          expect(
            tester
                .widget<GroupLiveBanner>(find.byType(GroupLiveBanner))
                .session
                .id,
            'live-2',
          );
        }
        expect(fixture.changed.where((session) => session?.id == 'live-1'),
            isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
