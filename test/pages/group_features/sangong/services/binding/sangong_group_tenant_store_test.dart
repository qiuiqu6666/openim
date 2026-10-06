import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/models/binding/sangong_group_tenant_state.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_my_config.dart';
import 'package:openim/pages/group_features/sangong/services/binding/sangong_group_tenant_store.dart';

import '../../sangong_test_support.dart';

class _Fixture {
  _Fixture() {
    context = snapshot();
    store = SangongGroupTenantStore(
      readContext: () => context,
      isCurrent: () =>
          active &&
          api.privilege
              .allows(userID: context.currentUserID, baseUrl: api.baseUrl),
      onChanged: () => notifications++,
    );
  }

  final api = SangongTestApi();
  late GroupFeatureContext context;
  late final SangongGroupTenantStore store;
  bool active = true;
  int notifications = 0;

  GroupFeatureContext snapshot(
          {String group = 'group-A', String user = 'owner'}) =>
      GroupFeatureContext(
        groupID: group,
        groupName: '当前群绑定缓存测试',
        currentUserID: user,
        gameType: GroupGameType.sangong,
        api: api,
        accountPrivilege: api.privilege,
        isGroupAdmin: true,
        sessionCurrent: () => active,
        onFeaturesChanged: (_) {},
        readContext: () => context,
      );

  Map<String, dynamic> response(String name, {String group = 'group-A'}) => {
        ...sangongConfig(name: name, group: group, tenant: group),
        'active': true,
      };

  SangongGroupTenantState saved(String name, {String group = 'group-A'}) =>
      SangongGroupTenantState(
        status: SangongGroupTenantStatus.configured,
        tenantId: group,
        config: SangongMyConfig.fromJson(response(name, group: group)),
      );

  Future<void> dispose() async {
    active = false;
    store.invalidate();
    await api.closeStreams();
    api.privilege.dispose();
  }
}

void main() {
  test(
      'a replacement context for the same account and group accepts its pending lookup',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final reply = Completer<dynamic>();
    fixture.api.respond = (_) => reply.future;
    final previous = fixture.context;
    final pending = fixture.store.refresh();
    fixture.context = fixture.snapshot();
    expect(identical(previous, fixture.context), isFalse);

    reply.complete(fixture.response('当前群远端配置'));
    final result = await pending;
    expect(result.config!.name, '当前群远端配置');
    expect(identical(fixture.store.state, result), isTrue);
    expect(fixture.store.error, isNull);
    expect(fixture.store.loading, isFalse);
    expect(fixture.api.calls.length, 1);
  });

  test('concurrent refreshes merge, reuse the cache and allow a forced reload',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final reply = Completer<dynamic>();
    fixture.api.respond = (_) => reply.future;
    final first = fixture.store.refresh();
    final second = fixture.store.refresh();
    final forcedWhilePending = fixture.store.refresh(force: true);
    expect(identical(first, second), isTrue);
    expect(identical(first, forcedWhilePending), isTrue);
    expect(fixture.api.calls.length, 1);

    reply.complete(fixture.response('初次读取'));
    final result = await first;
    expect(identical(await fixture.store.refresh(), result), isTrue);
    expect(fixture.api.calls.length, 1);

    fixture.api.respond = (_) => fixture.response('强制刷新');
    final refreshed = await fixture.store.refresh(force: true);
    expect(refreshed.config!.name, '强制刷新');
    expect(fixture.api.calls.length, 2);
    expect(fixture.store.loading, isFalse);
    expect(fixture.store.error, isNull);
  });

  for (final failed in [false, true]) {
    test('a newer save survives a superseded GET, failed=$failed', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final reply = Completer<dynamic>();
      fixture.api.respond = (_) => reply.future;
      final pending = fixture.store.refresh();
      final rejected = expectLater(pending,
          throwsA(failed ? isA<GroupFeatureException>() : isA<StateError>()));
      final saved = fixture.saved('保存确认的新配置');
      fixture.store.applySaved(saved);
      expect(fixture.store.loading, isFalse);

      if (failed) {
        reply.completeError(
            const GroupFeatureException('旧请求失败', code: 'SERVICE_UNAVAILABLE'));
      } else {
        reply.complete(fixture.response('保存之前的旧配置'));
      }
      await rejected;
      expect(identical(fixture.store.state, saved), isTrue);
      expect(fixture.store.state!.config!.name, '保存确认的新配置');
      expect(fixture.store.error, isNull);
      expect(identical(await fixture.store.refresh(), saved), isTrue);
      expect(fixture.api.calls.length, 1);
    });
  }

  for (final accountChanged in [false, true]) {
    test(
        'an old lookup cannot replace the new group/account state, accountChanged=$accountChanged',
        () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final reply = Completer<dynamic>();
      fixture.api.respond = (_) => reply.future;
      final pending = fixture.store.refresh();
      final rejected = expectLater(
          pending,
          throwsA(isA<GroupFeatureException>()
              .having((error) => error.code, 'code', 'SESSION_CHANGED')));
      final nextGroup = accountChanged ? 'group-A' : 'group-B';
      fixture.context = fixture.snapshot(
          group: nextGroup, user: accountChanged ? 'another-owner' : 'owner');
      fixture.store.invalidate();
      final nextState = fixture.saved('新上下文确认的配置', group: nextGroup);
      fixture.store.applySaved(nextState);

      reply.complete(fixture.response('旧群/旧账号的配置'));
      await rejected;
      expect(identical(fixture.store.state, nextState), isTrue);
      expect(fixture.store.state!.config!.name, '新上下文确认的配置');
      expect(fixture.store.error, isNull);
      expect(fixture.store.loading, isFalse);
    });
  }

  test(
      'privilege revocation discards a pending lookup and refuses cache restoration',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final reply = Completer<dynamic>();
    fixture.api.respond = (_) => reply.future;
    final pending = fixture.store.refresh();
    final rejected = expectLater(
        pending,
        throwsA(isA<GroupFeatureException>()
            .having((error) => error.code, 'code', 'PRIVILEGE_CHANGED')));
    fixture.api.privilege.setAllowed(false);
    fixture.store.invalidate();
    reply.complete(fixture.response('撤权前的配置'));
    await rejected;

    fixture.store.applySaved(fixture.saved('不应恢复的缓存'));
    expect(fixture.store.state, isNull);
    expect(fixture.store.error, isNull);
    expect(fixture.store.loading, isFalse);
    await expectLater(fixture.store.refresh(), throwsA(isA<StateError>()));
    expect(fixture.api.calls.length, 1);
  });
}
