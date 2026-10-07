import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_entry_scope.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_ledger_floating_entry.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_panel.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sangong_test_support.dart';

const _unavailableKey = ValueKey('sangong-profile-ledger-unavailable');
const _permissionMessage = '没有当前群的三公配置或运营权限';

class _RefreshingPrivilege extends FixtureAccountPrivilege {
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

GroupInfo _group(String id, {String? name, bool enabled = false}) =>
    GroupInfo.fromJson({
      'groupID': id,
      'groupName': name ?? '游戏群$id',
      if (enabled)
        'ex': jsonEncode({
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 1,
            'games': {
              'sangong': {'enabled': true, 'manageEntry': true}
            }
          }
        }),
    });

dynamic _response(SangongCall call, {bool manage = false}) {
  if (call.path.endsWith('/feature-capabilities')) {
    return {
      'groupID': Uri.decodeComponent(call.path.split('/')[3]),
      'capabilityVersion': 1,
      'sangong': {
        'canManage': manage,
        'canConfigure': false,
        if (manage) 'tenantID': 'tenant-authorized',
      },
    };
  }
  if (call.path.endsWith('/user')) {
    return {
      'exists': true,
      'user': {'userId': 19, 'imUserId': 'target', 'balance': 420}
    };
  }

  return sangongFixtureResponse(call);
}

GroupFeatureStore _store(
        SangongTestApi api, FixtureAccountPrivilege privilege) =>
    GroupFeatureStore(
      api: api,
      accountPrivilege: privilege,
      sessionCurrent: () => true,
      fetchGroups: (_) async => [],
    );

Future<void> _mount(
  WidgetTester tester, {
  required GroupFeatureStore store,
  required Future<List<GroupInfo>> Function() groups,
  bool dark = false,
  String target = 'target',
  ValueChanged<SangongProfileEntryScope?>? observe,
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    home: Scaffold(
      body: SangongProfileSurface(
        userID: target,
        store: store,
        loadGroups: groups,
        child: Builder(builder: (context) {
          observe?.call(SangongProfileEntryScope.maybeOf(context));
          return SingleChildScrollView(
            child: Column(children: [
              const Text('普通资料'),
              SangongInlineProfilePanel(userID: target),
            ]),
          );
        }),
      ),
    ),
  ));
  await flushSangong(tester);
  await tester.pumpAndSettle();
}

Finder get _ledgerInk => find.descendant(
    of: find.byType(SangongProfileLedgerFloatingEntry),
    matching: find.byType(InkWell));

Finder _inSheet(Finder matching) =>
    find.descendant(of: find.byKey(_unavailableKey), matching: matching);

Future<void> _openLedger(WidgetTester tester) async {
  expect(tester.widget<InkWell>(_ledgerInk).onTap, isNotNull);
  await tester.tap(_ledgerInk);
  await flushSangong(tester);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    OpenIM.iMManager.userID = 'owner';
    SharedPreferences.setMockInitialValues({});
  });

  for (final dark in [false, true]) {
    testWidgets(
        'tapping the actual ledger opens the unavailable sheet dark=$dark',
        (tester) async {
      final api = SangongTestApi()..respond = (call) => _response(call);
      final store = _store(api, FixtureAccountPrivilege());
      await _mount(tester,
          store: store, dark: dark, groups: () async => [_group('g')]);
      final callsBefore = api.calls.length;
      await _openLedger(tester);
      expect(find.byKey(_unavailableKey), findsOneWidget);
      expect(_inSheet(find.text('游戏流水')), findsOneWidget);
      expect(_inSheet(find.text(_permissionMessage)), findsOneWidget);
      expect(Theme.of(tester.element(find.byKey(_unavailableKey))).brightness,
          dark ? Brightness.dark : Brightness.light);
      expect(api.calls.length, callsBefore);
      expect(
          api.calls
              .every((call) => call.path.endsWith('/feature-capabilities')),
          isTrue);
      expect(tester.takeException(), isNull);
      await unmountSangong(tester);
      store.dispose();
    });
  }

  testWidgets(
      'the actual ledger opens an actionable explanation with no groups',
      (tester) async {
    final api = SangongTestApi();
    final store = _store(api, FixtureAccountPrivilege());
    await _mount(tester, store: store, groups: () async => []);
    await _openLedger(tester);
    expect(find.byKey(_unavailableKey), findsOneWidget);
    expect(_inSheet(find.text('暂无已加入的群聊，请加入群聊后重试')), findsOneWidget);
    expect(_inSheet(find.text('重试')), findsOneWidget);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets('sheet retry closes it and rereads real group permission',
      (tester) async {
    var capabilityReads = 0;
    var groupReads = 0;
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/feature-capabilities')) {
          return _response(call, manage: ++capabilityReads > 1);
        }
        return _response(call);
      };
    final store = _store(api, FixtureAccountPrivilege());
    await _mount(tester, store: store, groups: () async {
      groupReads++;
      return [_group('g', enabled: true)];
    });
    await _openLedger(tester);
    expect(api.count('/user'), 0);
    await tester.tap(_inSheet(find.text('重试')));
    await flushSangong(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(_unavailableKey), findsNothing);
    expect(groupReads, 2);
    expect(capabilityReads, 2);
    expect(find.textContaining('当前积分 420'), findsOneWidget);
    expect(api.count('/user'), 1);
    expect(find.text('普通资料'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets('ledger group selection preserves the opaque group ID',
      (tester) async {
    const opaqueID = 'G@Opaque_02/原始';
    final api = SangongTestApi()..respond = (call) => _response(call);
    final store = _store(api, FixtureAccountPrivilege());
    SangongProfileEntryScope? entry;
    await _mount(tester,
        store: store,
        groups: () async => [
              _group('@Opaque_Group-A', name: '第一群'),
              _group(opaqueID, name: '第二群'),
            ],
        observe: (value) => entry = value);
    await _openLedger(tester);
    expect(api.calls, isEmpty);
    await tester.tap(_inSheet(find.text('第二群')));
    await flushSangong(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(_unavailableKey), findsNothing);
    expect(entry?.selectedGroupID, opaqueID);
    expect(api.calls.single.path,
        '/chat/groups/${Uri.encodeComponent(opaqueID)}/feature-capabilities');
    expect(find.text(_permissionMessage), findsOneWidget);
    expect(find.text('普通资料'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets(
      'revoking privilege closes the public ledger and keeps the profile',
      (tester) async {
    final privilege = FixtureAccountPrivilege();
    final api = SangongTestApi()..respond = (call) => _response(call);
    final store = _store(api, privilege);
    await _mount(tester, store: store, groups: () async => [_group('g')]);
    await _openLedger(tester);
    privilege.setAllowed(false);
    await tester.pumpAndSettle();
    expect(find.byKey(_unavailableKey), findsNothing);
    expect(find.byType(SangongProfileLedgerFloatingEntry), findsNothing);
    expect(find.text('普通资料'), findsOneWidget);
    expect(api.count('/user'), 0);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets('replacing the target closes the captured public ledger route',
      (tester) async {
    final api = SangongTestApi()..respond = (call) => _response(call);
    final store = _store(api, FixtureAccountPrivilege());
    Future<List<GroupInfo>> groups() async => [_group('g')];
    await _mount(tester, store: store, groups: groups);
    await _openLedger(tester);
    await _mount(tester, store: store, groups: groups, target: 'new-target');
    expect(find.byKey(_unavailableKey), findsNothing);
    expect(find.text('普通资料'), findsOneWidget);
    expect(find.byType(SangongProfileLedgerFloatingEntry), findsOneWidget);
    expect(api.count('/user'), 0);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets('replacing the owner store closes only its public ledger route',
      (tester) async {
    final oldApi = SangongTestApi()..respond = (call) => _response(call);
    final oldStore = _store(oldApi, FixtureAccountPrivilege());
    await _mount(tester, store: oldStore, groups: () async => [_group('g')]);
    await _openLedger(tester);
    OpenIM.iMManager.userID = 'new-owner';
    final newApi = SangongTestApi()..respond = (call) => _response(call);
    final newStore = _store(newApi, FixtureAccountPrivilege());
    await _mount(tester, store: newStore, groups: () async => []);
    expect(find.byKey(_unavailableKey), findsNothing);
    expect(find.text('普通资料'), findsOneWidget);
    expect(oldApi.count('/user'), 0);
    expect(newApi.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    oldStore.dispose();
    newStore.dispose();
  });

  testWidgets('entry profile refresh failure refuses the ledger route',
      (tester) async {
    final privilege = _RefreshingPrivilege();
    final api = SangongTestApi()..respond = (call) => _response(call);
    final store = _store(api, privilege);
    await _mount(tester, store: store, groups: () async => [_group('g')]);
    expect(privilege.refreshCount, 1);
    privilege.read = () async => throw StateError('profile refresh failed');
    await _openLedger(tester);
    expect(privilege.refreshCount, 2);
    expect(find.byKey(_unavailableKey), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('普通资料'), findsOneWidget);
    expect(api.count('/user'), 0);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets(
      'revocation removes its covered sheet while keeping an ordinary dialog',
      (tester) async {
    final privilege = FixtureAccountPrivilege();
    final api = SangongTestApi()..respond = (call) => _response(call);
    final store = _store(api, privilege);
    await _mount(tester, store: store, groups: () async => [_group('g')]);
    await _openLedger(tester);
    unawaited(showDialog<void>(
      context: tester.element(find.byKey(_unavailableKey)),
      builder: (context) => AlertDialog(
        title: const Text('普通确认弹窗'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭普通弹窗'),
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('普通确认弹窗'), findsOneWidget);
    // A subsequent fresh grant must not revive the already revoked route.
    privilege.setAllowed(false);
    privilege.setAllowed(true);
    await flushSangong(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(_unavailableKey, skipOffstage: false), findsNothing);
    expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    expect(find.text('普通确认弹窗'), findsOneWidget);
    await tester.tap(find.text('关闭普通弹窗'));
    await tester.pumpAndSettle();
    expect(find.text('普通确认弹窗'), findsNothing);
    expect(find.text('普通资料'), findsOneWidget);
    expect(api.count('/user'), 0);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets('replacing the target and store closes a pending entry refresh',
      (tester) async {
    final privilege = _RefreshingPrivilege();
    final oldApi = SangongTestApi()..respond = (call) => _response(call);
    final oldStore = _store(oldApi, privilege);
    await _mount(tester, store: oldStore, groups: () async => [_group('old')]);
    final refresh = Completer<bool>();
    privilege.read = () => refresh.future;
    await tester.tap(_ledgerInk);
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(privilege.refreshCount, 2);
    final newApi = SangongTestApi()..respond = (call) => _response(call);
    final newStore = _store(newApi, FixtureAccountPrivilege());
    await _mount(tester,
        store: newStore,
        target: 'new-target',
        groups: () async => [_group('new')]);
    expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    expect(find.text('普通资料'), findsOneWidget);
    refresh.complete(true);
    await flushSangong(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(_unavailableKey, skipOffstage: false), findsNothing);
    expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    expect(oldApi.count('/user'), 0);
    expect(newApi.count('/user'), 0);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    oldStore.dispose();
    newStore.dispose();
  });

  testWidgets('repeated ledger triggers do not stack sheets while refreshing',
      (tester) async {
    final privilege = _RefreshingPrivilege();
    final api = SangongTestApi()..respond = (call) => _response(call);
    final store = _store(api, privilege);
    await _mount(tester, store: store, groups: () async => [_group('g')]);
    final refresh = Completer<bool>();
    privilege.read = () => refresh.future;
    await tester.tap(_ledgerInk);
    tester
        .widget<SangongProfileLedgerFloatingEntry>(
            find.byType(SangongProfileLedgerFloatingEntry))
        .onOpenLedger!();
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(privilege.refreshCount, 2);
    refresh.complete(true);
    await flushSangong(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(_unavailableKey), findsOneWidget);
    Navigator.of(tester.element(find.byKey(_unavailableKey))).pop();
    await tester.pumpAndSettle();
    await _openLedger(tester);
    expect(find.byKey(_unavailableKey), findsOneWidget);
    expect(privilege.refreshCount, 3);
    expect(api.count('/user'), 0);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    store.dispose();
  });
}
