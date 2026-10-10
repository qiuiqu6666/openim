import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/live/widgets/live_list_scope.dart';
import 'package:openim/pages/group_features/widgets/group_live_avatar.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'live_test_support.dart';

Map<String, dynamic> _live(String groupID,
        {bool active = true, String status = 'AUTHORIZED'}) =>
    {
      'active': active,
      if (active)
        'session': {
          ...liveDTO(status: status, id: 'live-$groupID'),
          'groupId': groupID,
        },
    };

String _requestedGroup(String path) => Uri.decodeComponent(
    path.split('/groups/').last.split('/live/current').first);

class _Fixture {
  _Fixture() {
    transport = LiveTransport((request) {
      final id = _requestedGroup(request.path);
      return pending[id]?.future ?? replies[id] ?? _live(id);
    });
    store = GroupFeatureStore(
      api: transport.api(),
      sessionCurrent: () => accountCurrent,
      fetchGroups: (ids) async {
        metadataReads.addAll(ids);
        return [for (final id in ids) GroupInfo(groupID: id)];
      },
    );
  }

  late final LiveTransport transport;
  late final GroupFeatureStore store;
  final active = ValueNotifier(true);
  final showAvatar = ValueNotifier(true);
  final pending = <String, Completer<Map<String, dynamic>>>{};
  final replies = <String, Map<String, dynamic>>{};
  final metadataReads = <String>[];
  final navigator = GlobalKey<NavigatorState>();
  bool accountCurrent = true;

  List<String> get reads => transport.requests
      .where((request) => request.path.endsWith('/current'))
      .map((request) => _requestedGroup(request.path))
      .toList();

  Widget avatar(String groupID) => GroupLiveAvatar(
        key: ValueKey('avatar-$groupID'),
        store: store,
        groupID: groupID,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: ColoredBox(color: Colors.blue),
        ),
      );

  Widget app({Brightness brightness = Brightness.light, bool list = false}) =>
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, isActive, __) => GroupLiveListScope(
              store: store,
              userID: 'self',
              sessionCurrent: () => accountCurrent,
              active: isActive,
              child: list
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        height: 200,
                        child: ListView.builder(
                          key: const ValueKey('groups'),
                          cacheExtent: 1000,
                          itemExtent: 100,
                          itemCount: 3115,
                          itemBuilder: (_, index) =>
                              Center(child: avatar('group-$index')),
                        ),
                      ),
                    )
                  : ValueListenableBuilder<bool>(
                      valueListenable: showAvatar,
                      builder: (_, shown, __) => shown
                          ? Align(
                              alignment: Alignment.topLeft,
                              child: avatar('group#1'))
                          : const SizedBox.shrink(),
                    ),
            ),
          ),
        ),
      );

  void notice(String groupID) => store.receiveBusiness(jsonEncode({
        'key': 'groupLiveChanged',
        'data': {'groupID': groupID}
      }));

  void dispose() {
    active.dispose();
    showAvatar.dispose();
    store.dispose();
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 10));
    VisibilityDetectorController.instance.notifyNow();
  }
}

Future<void> _mount(WidgetTester tester, _Fixture fixture,
    {Brightness brightness = Brightness.light, bool list = false}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.view.physicalSize = const Size(390, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(fixture.app(brightness: brightness, list: list));
  await _frames(tester);
}

void main() {
  late _Fixture fixture;
  late Duration previousVisibilityInterval;
  setUp(() {
    previousVisibilityInterval =
        VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    fixture = _Fixture();
  });
  tearDown(() {
    fixture.dispose();
    VisibilityDetectorController.instance.updateInterval =
        previousVisibilityInterval;
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    VisibilityDetectorController.instance.notifyNow();
    await tester.pump();
  }

  for (final brightness in Brightness.values) {
    testWidgets('$brightness visible avatar discovers live from current DTO',
        (tester) async {
      await _mount(tester, fixture, brightness: brightness);
      expect(fixture.reads, ['group#1']);
      expect(find.text('有直播'), findsOneWidget);
      expect(fixture.store.features('group#1').valid, false);
      expect(fixture.store.liveFeature('group#1').isActive, true);
      await tester.pumpWidget(fixture.app(brightness: brightness));
      await _frames(tester);
      expect(fixture.reads, ['group#1']);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

  testWidgets('group-only notices update LIVE and remove the ended badge',
      (tester) async {
    await _mount(tester, fixture);
    fixture.replies['group#1'] = _live('group#1', status: 'LIVE');
    fixture.notice('unrelated-group');
    await tester.pump(const Duration(milliseconds: 300));
    await _frames(tester);
    expect(fixture.reads.length, 1);
    fixture.notice('group#1');
    await tester.pump(const Duration(milliseconds: 300));
    await _frames(tester);
    expect(find.text('直播中'), findsOneWidget);
    expect(find.text('有直播'), findsNothing);
    expect(fixture.reads.length, 2);
    fixture.replies['group#1'] = _live('group#1', active: false);
    fixture.notice('group#1');
    await tester.pump(const Duration(milliseconds: 300));
    await _frames(tester);
    expect(find.text('直播中'), findsNothing);
    expect(find.text('有直播'), findsNothing);
    expect(fixture.store.liveFeature('group#1').isActive, false);
    expect(fixture.store.features('group#1').valid, false);
    expect(fixture.reads.length, 3);
    await unmount(tester);
  });

  testWidgets('inactive tab performs no reads and activation calibrates now',
      (tester) async {
    fixture.active.value = false;
    await _mount(tester, fixture);
    expect(fixture.reads, isEmpty);
    expect(find.text('有直播'), findsNothing);
    fixture.active.value = true;
    await _frames(tester);
    expect(fixture.reads, ['group#1']);
    expect(find.text('有直播'), findsOneWidget);
    fixture.active.value = false;
    await _frames(tester);
    fixture.replies['group#1'] = _live('group#1', active: false);
    fixture.notice('group#1');
    await tester.pump(const Duration(seconds: 46));
    await _frames(tester);
    expect(fixture.reads.length, 1);
    fixture.active.value = true;
    await _frames(tester);
    expect(fixture.reads.length, 2);
    expect(find.text('有直播'), findsNothing);
    await unmount(tester);
  });

  testWidgets('background stops reads and foreground refreshes visible groups',
      (tester) async {
    await _mount(tester, fixture);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    fixture.replies['group#1'] = _live('group#1', active: false);
    fixture.notice('group#1');
    await tester.pump(const Duration(seconds: 46));
    await _frames(tester);
    expect(fixture.reads.length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester);
    expect(fixture.reads.length, 2);
    expect(find.text('有直播'), findsNothing);
    await unmount(tester);
  });

  testWidgets('covered ModalRoute stops reads and returning refreshes now',
      (tester) async {
    await _mount(tester, fixture);
    unawaited(fixture.navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('另一页面')),
    )));
    await tester.pumpAndSettle();
    fixture.replies['group#1'] = _live('group#1', active: false);
    fixture.notice('group#1');
    await tester.pump(const Duration(seconds: 46));
    await _frames(tester);
    expect(fixture.reads.length, 1);
    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await _frames(tester);
    expect(fixture.reads.length, 2);
    expect(find.text('有直播'), findsNothing);
    await unmount(tester);
  });

  testWidgets('ListView cached avatars query only groups inside the viewport',
      (tester) async {
    await _mount(tester, fixture, list: true);
    expect(find.byType(GroupLiveAvatar, skipOffstage: false).evaluate().length,
        greaterThan(2));
    expect(fixture.reads.toSet(), {'group-0', 'group-1'});
    expect(fixture.metadataReads.toSet(), {'group-0', 'group-1'});
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(1000);
    await _frames(tester);
    expect(
        fixture.reads.toSet(), {'group-0', 'group-1', 'group-10', 'group-11'});
    expect(fixture.reads.length, 4);
    expect(fixture.metadataReads.toSet(),
        {'group-0', 'group-1', 'group-10', 'group-11'});
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final boundary in ['inactive', 'last row disposed']) {
    testWidgets('$boundary blocks an in-flight no-summary DTO from the badge',
        (tester) async {
      final response = Completer<Map<String, dynamic>>();
      fixture.pending['group#1'] = response;
      await _mount(tester, fixture);
      expect(fixture.reads, ['group#1']);
      expect(find.text('有直播'), findsNothing);
      if (boundary == 'inactive') {
        fixture.active.value = false;
      } else {
        fixture.showAvatar.value = false;
      }
      await _frames(tester);
      response.complete(_live('group#1'));
      await _frames(tester);
      expect(fixture.store.liveFeature('group#1').isActive, false);
      expect(fixture.store.features('group#1').valid, false);
      expect(find.text('有直播'), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }
}
