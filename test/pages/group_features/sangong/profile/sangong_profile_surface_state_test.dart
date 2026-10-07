import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_entry_scope.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_panel.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_surface.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_ledger_floating_entry.dart';
import '../sangong_test_support.dart';

class _RefreshingPrivilege extends FixtureAccountPrivilege {
  _RefreshingPrivilege({super.allowed});
  Future<bool> Function()? read;
  @override
  Future<bool> refresh() async {
    refreshCount++;
    try {
      final allowed = read == null
          ? allows(userID: 'owner', baseUrl: 'https://fixture.example')
          : await read!();
      setAllowed(allowed);
      return allowed;
    } catch (_) {
      setAllowed(false);
      return false;
    }
  }
}

GroupInfo _group(String id, {bool enabled = false}) => GroupInfo.fromJson({
      'groupID': id,
      'groupName': '群$id',
      if (enabled)
        'ex': jsonEncode({
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 1,
            'games': {
              'sangong': {'enabled': true, 'manageEntry': true}
            }
          }
        })
    });

Map<String, dynamic> _capabilities(String group, {bool manage = false}) => {
      'groupID': group,
      'capabilityVersion': 1,
      'sangong': {
        'canManage': manage,
        if (manage) 'tenantID': 'tenant-authorized'
      }
    };

dynamic _profileResponse(SangongCall call) {
  if (call.path.endsWith('/feature-capabilities')) {
    return _capabilities(call.path.split('/')[3]);
  }
  if (call.path.endsWith('/user')) {
    return {
      'exists': true,
      'user': {'userId': 19, 'imUserId': 'target', 'balance': 420}
    };
  }

  return sangongFixtureResponse(call);
}

Future<void> _mountSurface(WidgetTester tester,
    {required GroupFeatureStore store,
    required Future<List<GroupInfo>> Function() groups,
    String userID = 'target',
    String? groupID,
    bool dark = false,
    void Function(SangongProfileEntryScope?)? observe}) async {
  await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
          body: SangongProfileSurface(
              userID: userID,
              groupID: groupID,
              store: store,
              loadGroups: groups,
              child: Builder(builder: (context) {
                observe?.call(SangongProfileEntryScope.maybeOf(context));
                return SingleChildScrollView(
                    child: Column(children: [
                  const Text('普通资料'),
                  SangongInlineProfilePanel(userID: userID),
                ]));
              })))));
  await flushSangong(tester);
}

GroupFeatureStore _store(SangongTestApi api, FixtureAccountPrivilege privilege,
        {bool Function()? sessionCurrent}) =>
    GroupFeatureStore(
        api: api,
        accountPrivilege: privilege,
        sessionCurrent: sessionCurrent ?? (() => true),
        fetchGroups: (_) async => []);

void main() {
  setUp(() => OpenIM.iMManager.userID = 'owner');

  for (final dark in [false, true]) {
    testWidgets(
        'fresh grant exposes services without old group metadata dark=$dark',
        (tester) async {
      final response = Completer<bool>();
      final privilege = _RefreshingPrivilege(allowed: false)
        ..read = () => response.future;
      final api = SangongTestApi()..respond = _profileResponse;
      final store = _store(api, privilege);
      var groupReads = 0;
      await _mountSurface(tester, store: store, dark: dark, groups: () async {
        groupReads++;
        return [_group('normal')];
      });
      expect(
          find.byKey(const ValueKey('sangong-profile-services')), findsNothing);
      response.complete(true);
      await flushSangong(tester);
      expect(find.byKey(const ValueKey('sangong-profile-services')),
          findsOneWidget);
      expect(find.text('没有当前群的三公配置或运营权限'), findsOneWidget);
      expect(find.text('普通资料'), findsOneWidget);
      expect(privilege.refreshCount, 1);
      expect(groupReads, 1);
      expect(api.count('/feature-capabilities'), 1);
      expect(
          api.calls.any(
              (call) => call.useBearerAuth && call.path.contains('/admin/')),
          isFalse);
      expect(tester.takeException(), isNull);
      await unmountSangong(tester);
      store.dispose();
    });
  }

  for (final throws in [false, true]) {
    testWidgets(
        'entry refresh failure hides a previously granted flag throws=$throws',
        (tester) async {
      final privilege = _RefreshingPrivilege()
        ..read = () async {
          if (throws) throw StateError('network failure');
          return false;
        };
      final api = SangongTestApi();
      final store = _store(api, privilege);
      var groupReads = 0;
      await _mountSurface(tester, store: store, groups: () async {
        groupReads++;
        return [_group('g')];
      });
      expect(
          find.byKey(const ValueKey('sangong-profile-services')), findsNothing);
      expect(find.text('普通资料'), findsOneWidget);
      expect(groupReads, 0);
      expect(api.calls, isEmpty);
      await unmountSangong(tester);
      store.dispose();
    });
  }

  testWidgets(
      'zero joined groups still shows services and an actionable explanation',
      (tester) async {
    final api = SangongTestApi();
    final store = _store(api, FixtureAccountPrivilege());
    await _mountSurface(tester, store: store, groups: () async => []);
    expect(
        find.byKey(const ValueKey('sangong-profile-services')), findsOneWidget);
    expect(find.text('暂无已加入的群聊，请加入群聊后重试'), findsOneWidget);
    final ledger = find.byType(SangongProfileLedgerFloatingEntry);
    expect(
        tester.widget<SangongProfileLedgerFloatingEntry>(ledger).onOpenLedger,
        isNotNull);
    expect(find.text('重试'), findsOneWidget);
    expect(api.calls, isEmpty);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets(
      'group lookup error is visible and retry refreshes the same profile',
      (tester) async {
    final api = SangongTestApi()..respond = _profileResponse;
    final privilege = _RefreshingPrivilege();
    final store = _store(api, privilege);
    var groupReads = 0;
    await _mountSurface(tester, store: store, groups: () async {
      if (++groupReads == 1) throw StateError('群列表读取失败');
      return [_group('g')];
    });
    expect(find.text('群列表读取失败'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('sangong-profile-services')), findsOneWidget);
    await tester.tap(find.text('重试'));
    await flushSangong(tester);
    expect(groupReads, 2);
    expect(privilege.refreshCount, 2);
    expect(find.text('没有当前群的三公配置或运营权限'), findsOneWidget);
    expect(api.count('/feature-capabilities'), 1);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets(
      'capability service failure remains visible and retry can authorize real data',
      (tester) async {
    final api = SangongTestApi();
    var reads = 0;
    api.respond = (call) {
      if (call.path.endsWith('/feature-capabilities')) {
        if (++reads == 1) {
          throw const GroupFeatureException('该功能的服务暂未开通', unavailable: true);
        }
        return _capabilities('g', manage: true);
      }
      return _profileResponse(call);
    };
    final store = _store(api, FixtureAccountPrivilege());
    await _mountSurface(tester,
        store: store, groups: () async => [_group('g', enabled: true)]);
    expect(
        find.byKey(const ValueKey('sangong-profile-services')), findsOneWidget);
    expect(find.text('该功能的服务暂未开通'), findsOneWidget);
    expect(api.count('/user'), 0);
    await tester.tap(find.text('重试'));
    await flushSangong(tester);
    expect(find.textContaining('当前积分 420'), findsOneWidget);
    expect(api.count('/user'), 1);
    expect(api.count('/feature-capabilities'), 2);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets(
      'revocation discards a late group result and grant starts fresh discovery',
      (tester) async {
    final groups = Completer<List<GroupInfo>>();
    final privilege = FixtureAccountPrivilege();
    final api = SangongTestApi()..respond = _profileResponse;
    final store = _store(api, privilege);
    var groupReads = 0;
    await _mountSurface(tester, store: store, groups: () {
      return ++groupReads == 1 ? groups.future : Future.value([_group('new')]);
    });
    expect(
        find.byKey(const ValueKey('sangong-profile-services')), findsOneWidget);
    privilege.setAllowed(false);
    groups.complete([_group('old', enabled: true)]);
    await flushSangong(tester);
    expect(
        find.byKey(const ValueKey('sangong-profile-services')), findsNothing);
    expect(api.calls, isEmpty);
    privilege.setAllowed(true);
    await flushSangong(tester);
    expect(
        find.byKey(const ValueKey('sangong-profile-services')), findsOneWidget);
    expect(groupReads, 2);
    expect(api.calls.single.path, '/chat/groups/new/feature-capabilities');
    expect(store.cachedGroupInfo('old'), isNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets('late group result cannot expose services after owner changes',
      (tester) async {
    final groups = Completer<List<GroupInfo>>();
    final api = SangongTestApi()..respond = _profileResponse;
    final store = _store(api, FixtureAccountPrivilege());
    await _mountSurface(tester, store: store, groups: () => groups.future);
    OpenIM.iMManager.userID = 'other';
    groups.complete([_group('old', enabled: true)]);
    await flushSangong(tester);
    expect(
        find.byKey(const ValueKey('sangong-profile-services')), findsNothing);
    expect(find.text('普通资料'), findsOneWidget);
    expect(api.calls, isEmpty);
    expect(store.cachedGroupInfo('old'), isNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets(
      'multiple groups wait for explicit selection and late old permission is ignored',
      (tester) async {
    final oldPermission = Completer<dynamic>();
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path == '/chat/groups/a/feature-capabilities') {
          return oldPermission.future;
        }
        return _profileResponse(call);
      };
    final store = _store(api, FixtureAccountPrivilege());
    SangongProfileEntryScope? entry;
    await _mountSurface(tester,
        store: store,
        groups: () async => [_group('a'), _group('b')],
        observe: (value) => entry = value);
    expect(entry?.selectedGroupID, isNull);
    expect(api.calls, isEmpty);
    entry!.onSelectGroup('a');
    await flushSangong(tester);
    entry!.onSelectGroup('b');
    await flushSangong(tester);
    oldPermission.complete(_capabilities('a', manage: true));
    await flushSangong(tester);
    expect(entry?.selectedGroupID, 'b');
    expect(entry?.loading, isFalse);
    expect(entry?.onLedger, isNotNull);
    expect(find.text('没有当前群的三公配置或运营权限'), findsOneWidget);
    expect(api.count('/user'), 0);
    expect(api.count('/my-config'), 0);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets('group-member profile cannot select an unrelated returned group',
      (tester) async {
    final api = SangongTestApi();
    final store = _store(api, FixtureAccountPrivilege());
    await _mountSurface(tester,
        store: store,
        groupID: 'expected',
        groups: () async => [_group('unrelated', enabled: true)]);
    expect(
        find.byKey(const ValueKey('sangong-profile-services')), findsOneWidget);
    expect(find.text('暂无已加入的群聊，请加入群聊后重试'), findsOneWidget);
    expect(api.calls, isEmpty);
    expect(store.cachedGroupInfo('unrelated'), isNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets(
      'business revocation keeps public services but drops private account data',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/feature-capabilities')
          ? _capabilities('g', manage: true)
          : _profileResponse(call);
    final store = _store(api, FixtureAccountPrivilege());
    await _mountSurface(tester,
        store: store, groups: () async => [_group('g', enabled: true)]);
    expect(find.textContaining('当前积分 420'), findsOneWidget);
    store.invalidateCapabilities('g');
    await flushSangong(tester);
    expect(
        find.byKey(const ValueKey('sangong-profile-services')), findsOneWidget);
    expect(find.textContaining('当前积分 420'), findsNothing);
    expect(find.text('当前群的三公业务权限已变化，请重试'), findsOneWidget);
    expect(
        tester
            .widget<SangongProfileLedgerFloatingEntry>(
                find.byType(SangongProfileLedgerFloatingEntry))
            .onOpenLedger,
        isNotNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets(
      'dispose fences pending group discovery without affecting normal navigation',
      (tester) async {
    final groups = Completer<List<GroupInfo>>();
    final api = SangongTestApi();
    final store = _store(api, FixtureAccountPrivilege());
    await _mountSurface(tester, store: store, groups: () => groups.future);
    await unmountSangong(tester);
    groups.complete([_group('late', enabled: true)]);
    await flushSangong(tester);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    store.dispose();
  });
}
