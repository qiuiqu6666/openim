import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/mark_six/data/mark_six_repository.dart';
import 'package:openim/pages/group_features/mark_six/data/mark_six_controller.dart';
import 'package:openim/pages/group_features/mark_six/agent/data/agent_query_controller.dart';
import 'package:openim/pages/group_features/mark_six/agent/data/agent_descendants_controller.dart';
import 'package:openim/pages/group_features/mark_six/agent/data/agent_rebate_controller.dart';
import 'package:openim/pages/group_features/mark_six/agent/models/agent_date_range.dart';
import 'mark_six_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'same scoped query coalesces and expires; force still shares in-flight work',
      () async {
    var now = DateTime.utc(2026, 10, 4);
    final response = Completer<Map<String, dynamic>>();
    final api = MarkSixFakeApi(respond: (_, __, ___, ____) => response.future);
    final repo = MarkSixRepository(markSixContext(api), now: () => now);
    addTearDown(repo.close);
    final a = repo.read('/me/agent/rebate/current');
    final b = repo.read('/me/agent/rebate/current', force: true);
    expect(identical(a, b), isTrue);
    expect(api.calls, hasLength(1));
    expect(api.calls.single.headers['X-Group-Id'], 'group-test');
    response.complete({'value': 8});
    await a;
    await repo.read('/me/agent/rebate/current');
    expect(api.calls, hasLength(1));
    now = now.add(const Duration(seconds: 31));
    await repo.read('/me/agent/rebate/current');
    expect(api.calls, hasLength(2));
  });
  test('missing machine binding never requests demonstration data', () {
    final api = MarkSixFakeApi();
    final repo = MarkSixRepository(markSixContext(api, machine: ''));
    addTearDown(repo.close);
    expect(() => repo.lottery('draws'), throwsStateError);
    expect(api.calls, isEmpty);
  });
  test('account switch rejects late read and never caches the old response',
      () async {
    var current = true;
    final pending = Completer<Map<String, dynamic>>();
    final api = MarkSixFakeApi(respond: (_, __, ___, ____) => pending.future);
    final repo =
        MarkSixRepository(markSixContext(api, sessionCurrent: () => current));
    addTearDown(repo.close);
    final work = repo.read('/me/agent/rebate/current');
    final rejection = expectLater(work, throwsA(isA<MarkSixSessionEnded>()));
    current = false;
    pending.complete({'balance': 999});
    await rejection;
    expect(() => repo.read('/me/agent/rebate/current'),
        throwsA(isA<MarkSixSessionEnded>()));
    expect(api.calls, hasLength(1));
  });
  test(
      'permission invalidation blocks private late acknowledgement but preserves public draws',
      () async {
    var authorized = true;
    final pending = Completer<Map<String, dynamic>>();
    final api = MarkSixFakeApi(
        respond: (_, path, query, __) => path.startsWith('/me/')
            ? pending.future
            : markSixFixtureResponse(path, query));
    final repo = MarkSixRepository(
        markSixContext(api, capabilitiesCurrent: () => authorized));
    addTearDown(repo.close);
    final work = repo.read('/me/agent/rebate/current');
    final rejection = expectLater(work, throwsA(isA<MarkSixSessionEnded>()));
    authorized = false;
    pending.complete({'balance': 1});
    await rejection;
    // Async mutation rejects before reaching transport.
    await expectLater(repo.post('/me/agent/rebate/apply'),
        throwsA(isA<MarkSixSessionEnded>()));
    await repo.lottery('draws');
    expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
  });
  test('response group and targeted history IDs must agree with request scope',
      () async {
    final api =
        MarkSixFakeApi(respond: (_, __, ___, ____) => {'groupID': 'other'});
    final repo = MarkSixRepository(markSixContext(api));
    addTearDown(repo.close);
    await expectLater(
        repo.read('/me/agent/rebate/current'), throwsFormatException);
    api.respond =
        (_, __, ___, ____) => {'userId': 'self', 'targetUserId': 'other'};
    await expectLater(
        repo.read('/me/agent/descendants/history', query: {'userId': 'child'}),
        throwsFormatException);
    api.respond = (_, __, ___, ____) =>
        {'userId': 'self', 'targetUserId': 'child', 'items': []};
    await repo
        .read('/me/agent/descendants/history', query: {'userId': 'child'});
  });
  test(
      'drawer and full page share snapshot; predictions stay lazy and validate pagination',
      () async {
    final api = MarkSixFakeApi();
    final state = MarkSixController(MarkSixRepository(markSixContext(api)));
    addTearDown(state.dispose);
    final a = state.refresh(), b = state.refresh();
    expect(identical(a, b), isTrue);
    await a;
    expect(state.ready, isTrue);
    expect(state.latest?.id, '108');
    expect(api.calls, hasLength(2));
    expect(api.calls.any((c) => c.path.endsWith('/predictions')), isFalse);
    await state.loadPredictions();
    expect(state.predictions.single['issue'], '109');
    expect(api.calls.last.query, containsPair('window', 40));
    await state.loadPredictions();
    expect(api.calls, hasLength(3));
    api.respond = (_, path, query, __) => path.endsWith('/predictions')
        ? {'page': 99, 'window': query['window'], 'hasMore': false, 'items': []}
        : markSixFixtureResponse(path, query);
    await state.selectWindow(6);
    expect(state.predictionError, contains('分页'));
    expect(state.predictions, isEmpty);
  });
  test('disposed lottery controller ignores late snapshots and callbacks',
      () async {
    final pending = Completer<Map<String, dynamic>>();
    final api = MarkSixFakeApi(respond: (_, __, ___, ____) => pending.future);
    final state = MarkSixController(MarkSixRepository(markSixContext(api)));
    var notices = 0;
    state.addListener(() => notices++);
    final work = state.refresh();
    final before = notices;
    state.dispose();
    pending.complete({
      'data': {'items': []}
    });
    await work;
    expect(notices, before);
    expect(state.ready, isFalse);
  });
  test('changing history range ignores the previous range acknowledgement',
      () async {
    final old = Completer<Map<String, dynamic>>();
    final api = MarkSixFakeApi(
        respond: (_, __, query, ___) => query['startDate'] == 'old'
            ? old.future
            : {
                'total': {'totalFlow': 22}
              });
    final repo = MarkSixRepository(markSixContext(api));
    final state = AgentQueryController(repo);
    addTearDown(() {
      state.dispose();
      repo.close();
    });
    final first =
        state.load('/me/agent/rebate/history', query: {'startDate': 'old'});
    await state.load('/me/agent/rebate/history', query: {'startDate': 'new'});
    old.complete({
      'total': {'totalFlow': 99}
    });
    await first;
    expect(state.data?['total']['totalFlow'], 22);
    expect(state.loading, isFalse);
  });
  test('descendants pagination deduplicates IDs and retains orphan/cycle rows',
      () async {
    final api = MarkSixFakeApi(
        respond: (_, __, query, ___) => {
              'page': query['page'],
              'userId': 'self',
              'total': 3,
              'hasMore': query['page'] == 1,
              'items': query['page'] == 1
                  ? [
                      {'userId': 'a', 'directParentUserId': 'b'},
                      {'userId': 'b', 'directParentUserId': 'a'}
                    ]
                  : [
                      {'userId': 'a', 'balance': 8},
                      {'userId': 'c', 'directParentUserId': 'missing'}
                    ]
            });
    final repo = MarkSixRepository(markSixContext(api));
    final state = AgentDescendantsController(repo);
    addTearDown(() {
      state.dispose();
      repo.close();
    });
    await state.load();
    await state.load(more: true);
    expect(state.items, hasLength(3));
    expect(state.items.first['balance'], 8);
    expect(state.hasMore, isFalse);
    expect(agentVisibleRows(state.items, ownerID: 'self'), hasLength(3));
    await state.load(more: true);
    expect(api.calls, hasLength(2));
  });
  test(
      'permission event clears private projection and prevents further requests',
      () async {
    var authorized = true;
    final events = StreamController<Map<String, dynamic>>(sync: true);
    final api = MarkSixFakeApi();
    final repo = MarkSixRepository(markSixContext(api,
        capabilitiesCurrent: () => authorized, events: events.stream));
    final state = AgentQueryController(repo);
    var notifications = 0;
    state.addListener(() => notifications++);
    addTearDown(() {
      state.dispose();
      repo.close();
      events.close();
    });
    await state.load('/me/agent/rebate/current');
    expect(state.data, isNotNull);
    final before = notifications;
    authorized = false;
    events.add(
        {'key': 'groupFeatureCapabilitiesChanged', 'groupID': 'group-test'});
    expect(state.data, isNull);
    expect(notifications, before + 1);
    await state.load('/me/agent/rebate/current');
    expect(api.calls, hasLength(1));
  });
  test('background rebate state prevents status polling', () async {
    final api = MarkSixFakeApi();
    final repo = MarkSixRepository(markSixContext(api));
    final state = AgentRebateController(repo);
    addTearDown(() {
      state.dispose();
      repo.close();
    });
    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    await state.checkStatus();
    expect(api.calls, isEmpty);
  });
  for (final changed in [
    {'enabled': false, 'drawHistoryEntry': true, 'machineCode': 'machine-test'},
    {'enabled': true, 'drawHistoryEntry': false, 'machineCode': 'machine-test'},
    {'enabled': true, 'drawHistoryEntry': true, 'machineCode': 'machine-new'},
  ]) {
    test('public feature event retires its own Mark Six binding $changed',
        () async {
      final events = StreamController<Map<String, dynamic>>(sync: true);
      final api = MarkSixFakeApi();
      final state = MarkSixController(
          MarkSixRepository(markSixContext(api, events: events.stream)));
      addTearDown(() {
        state.dispose();
        events.close();
      });
      state.attach();
      await state.refresh();
      expect(state.ready, isTrue);
      events.add({
        'key': 'groupFeaturesChanged',
        'groupID': 'group-test',
        'data': {
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 2,
            'games': {'markSix': changed}
          }
        }
      });
      expect(state.scopeInvalidated, isTrue);
      expect(state.current, isFalse);
      expect(state.draws, isEmpty);
      expect(state.config, isNull);
      await state.refresh();
      expect(api.calls, hasLength(2));
    });
  }
  test(
      'private permissions and other game changes leave public Mark Six intact',
      () async {
    var authorized = true;
    final events = StreamController<Map<String, dynamic>>(sync: true);
    final api = MarkSixFakeApi();
    final state = MarkSixController(MarkSixRepository(markSixContext(api,
        capabilitiesCurrent: () => authorized, events: events.stream)));
    addTearDown(() {
      state.dispose();
      events.close();
    });
    state.attach();
    await state.refresh();
    authorized = false;
    events.add(
        {'key': 'groupFeatureCapabilitiesChanged', 'groupID': 'group-test'});
    events.add({
      'key': 'groupFeaturesChanged',
      'groupID': 'group-test',
      'data': {
        'groupFeatures': {
          'schemaVersion': 1,
          'revision': 2,
          'live': {'status': 'live'},
          'games': {
            'markSix': {
              'enabled': true,
              'drawHistoryEntry': true,
              'machineCode': 'machine-test'
            }
          }
        }
      }
    });
    expect(state.current, isTrue);
    expect(state.ready, isTrue);
    expect(api.calls, hasLength(2));
  });
  test(
      'China business date changes at 07:00 and presets preserve inclusive bounds',
      () {
    final before = agentRebateInstantFromChinaWall(2026, 10, 4, 6, 59, 59);
    final after = agentRebateInstantFromChinaWall(2026, 10, 4, 7);
    expect(AgentRebateDateRange.today(before).startApiValue, '2026-10-03');
    expect(AgentRebateDateRange.today(after).startApiValue, '2026-10-04');
    expect(AgentRebateDateRange.recentDays(90, after).inclusiveDays, 90);
    expect(() => AgentRebateDateRange.recentDays(94, after), throwsRangeError);
    expect(
        AgentRebateDateRange.validate(
            start: DateTime(2026, 10, 5),
            end: DateTime(2026, 10, 4),
            today: DateTime(2026, 10, 4)),
        AgentRebateDateRangeError.endBeforeStart);
  });
}
