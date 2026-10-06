import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/mark_six/data/mark_six_repository.dart';
import 'package:openim/pages/group_features/mark_six/agent/data/agent_rebate_controller.dart';
import 'mark_six_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'rebate requires confirmed status and never treats an empty response as success',
      () async {
    final api = MarkSixFakeApi(
        respond: (method, path, query, _) =>
            method == 'POST' ? {} : markSixFixtureResponse(path, query));
    final repo = MarkSixRepository(markSixContext(api));
    final state = AgentRebateController(repo);
    addTearDown(() {
      state.dispose();
      repo.close();
    });
    await state.initialize();
    await state.apply();
    expect(state.settled, isFalse);
    expect(state.applyError, contains('状态缺失'));
    expect(api.calls.where((c) => c.method == 'POST'), hasLength(1));
    expect(state.needsStatusQuery, isTrue);
    await state.apply();
    expect(api.calls.where((c) => c.method == 'POST'), hasLength(1));
    api.respond = (_, __, ___, ____) => {'status': 'FAILED'};
    await state.checkStatus();
    expect(state.needsStatusQuery, isFalse);
    api.respond = (method, path, query, _) => method == 'POST'
        ? {'status': 'SUCCESS'}
        : markSixFixtureResponse(path, query);
    await state.apply();
    expect(state.settled, isTrue);
    expect(state.data?['summary'], isNotEmpty);
  });
  test(
      'initialization shares status recovery and forbids POST before its acknowledgement',
      () async {
    final restored = Completer<Map<String, dynamic>>();
    final api = MarkSixFakeApi(
        respond: (_, path, query, __) => path.endsWith('/apply/status')
            ? restored.future
            : markSixFixtureResponse(path, query));
    final repo = MarkSixRepository(markSixContext(api));
    final state = AgentRebateController(repo);
    addTearDown(() {
      state.dispose();
      repo.close();
    });
    final first = state.initialize(), second = state.initialize();
    expect(state.restoring, isTrue);
    expect(state.statusRestored, isFalse);
    await state.apply();
    expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    expect(
        api.calls.where((c) => c.path.endsWith('/apply/status')), hasLength(1));
    restored.complete({'status': 'NONE'});
    await Future.wait([first, second]);
    expect(state.statusRestored, isTrue);
    expect(state.needsStatusQuery, isFalse);
    expect(api.calls, hasLength(2));
  });
  for (final response in [
    <String, dynamic>{},
    {'status': 'unknown'}
  ]) {
    test('missing or unknown restored status blocks further POST $response',
        () async {
      final api = MarkSixFakeApi(
          respond: (_, path, query, __) => path.endsWith('/apply/status')
              ? response
              : markSixFixtureResponse(path, query));
      final repo = MarkSixRepository(markSixContext(api));
      final state = AgentRebateController(repo);
      addTearDown(() {
        state.dispose();
        repo.close();
      });
      await state.initialize();
      expect(state.statusRestored, isFalse);
      expect(state.needsStatusQuery, isTrue);
      expect(state.applyError, contains('状态'));
      await state.apply();
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    });
  }
  test(
      'restoration failure remains locked and succeeds only after status retry',
      () async {
    var fail = true;
    final api = MarkSixFakeApi(respond: (_, path, query, __) {
      if (fail && path.endsWith('/apply/status')) throw StateError('查询失败');
      return markSixFixtureResponse(path, query);
    });
    final repo = MarkSixRepository(markSixContext(api));
    final state = AgentRebateController(repo);
    addTearDown(() {
      state.dispose();
      repo.close();
    });
    await state.initialize();
    expect(state.statusRestored, isFalse);
    expect(state.applyError, contains('查询失败'));
    await state.apply();
    expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    fail = false;
    await state.checkStatus();
    expect(state.statusRestored, isTrue);
    expect(state.canApply(), isTrue);
  });
  test('NONE in POST acknowledgement is unknown and cannot repeat submission',
      () async {
    final api = MarkSixFakeApi(
        respond: (method, path, query, _) => method == 'POST'
            ? {'status': 'NONE'}
            : markSixFixtureResponse(path, query));
    final repo = MarkSixRepository(markSixContext(api));
    final state = AgentRebateController(repo);
    addTearDown(() {
      state.dispose();
      repo.close();
    });
    await state.initialize();
    await state.apply();
    expect(state.uncertain, isTrue);
    expect(state.applyError, contains('状态缺失或未知'));
    await state.apply();
    expect(api.calls.where((c) => c.method == 'POST'), hasLength(1));
  });
  for (final amount in [null, 0, -1, 'invalid', double.infinity]) {
    test('unconfirmed or nonpositive outstanding amount blocks POST $amount',
        () async {
      final api = MarkSixFakeApi(
          respond: (_, path, query, __) => path.endsWith('/current')
              ? {
                  'summary': {'agentPendingRebate': amount}
                }
              : markSixFixtureResponse(path, query));
      final repo = MarkSixRepository(markSixContext(api));
      final state = AgentRebateController(repo);
      addTearDown(() {
        state.dispose();
        repo.close();
      });
      await state.initialize();
      expect(state.canApply(), isFalse);
      await state.apply();
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    });
  }
  test(
      'confirmed prior SUCCESS cannot be applied again even with stale positive amount',
      () async {
    final api = MarkSixFakeApi(
        respond: (_, path, query, __) => path.endsWith('/apply/status')
            ? {'status': 'SUCCESS'}
            : markSixFixtureResponse(path, query));
    final repo = MarkSixRepository(markSixContext(api));
    final state = AgentRebateController(repo);
    addTearDown(() {
      state.dispose();
      repo.close();
    });
    await state.initialize();
    expect(state.settled, isTrue);
    expect(state.canApply(), isFalse);
    await state.apply();
    expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
  });
  for (final revokeAccount in [false, true]) {
    test(
        'late restoration cannot unlock revoked ${revokeAccount ? 'account' : 'permission'}',
        () async {
      var current = true;
      final restored = Completer<Map<String, dynamic>>();
      final api = MarkSixFakeApi(
          respond: (_, path, query, __) => path.endsWith('/apply/status')
              ? restored.future
              : markSixFixtureResponse(path, query));
      final repo = MarkSixRepository(markSixContext(api,
          sessionCurrent: revokeAccount ? () => current : null,
          capabilitiesCurrent: revokeAccount ? null : () => current));
      final state = AgentRebateController(repo);
      addTearDown(() {
        state.dispose();
        repo.close();
      });
      final work = state.initialize();
      current = false;
      restored.complete({'status': 'NONE'});
      await work;
      expect(state.statusRestored, isFalse);
      expect(state.canApply(), isFalse);
      await state.apply();
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    });
  }
  test(
      'closing and reopening restores pending settlement and cannot repeat previous POST',
      () async {
    var serverStatus = 'NONE';
    final api = MarkSixFakeApi(respond: (method, path, query, _) {
      if (method == 'POST') {
        serverStatus = 'PROCESSING';
        return {'status': serverStatus};
      }
      if (path.endsWith('/apply/status')) return {'status': serverStatus};
      return markSixFixtureResponse(path, query);
    });
    final firstRepo = MarkSixRepository(markSixContext(api));
    final first = AgentRebateController(firstRepo);
    await first.initialize();
    final submitted = first.apply();
    first.dispose();
    firstRepo.close();
    await submitted;
    final nextRepo = MarkSixRepository(markSixContext(api));
    final reopened = AgentRebateController(nextRepo);
    addTearDown(() {
      reopened.dispose();
      nextRepo.close();
    });
    await reopened.initialize();
    expect(reopened.pending, isTrue);
    expect(reopened.needsStatusQuery, isTrue);
    await reopened.apply();
    expect(api.calls.where((c) => c.method == 'POST'), hasLength(1));
    serverStatus = 'SUCCESS';
    await reopened.checkStatus();
    expect(reopened.settled, isTrue);
    expect(reopened.needsStatusQuery, isFalse);
    expect(api.calls.where((c) => c.method == 'POST'), hasLength(1));
  });
}
