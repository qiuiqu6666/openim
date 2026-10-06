import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_entry_scope.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_panel.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_surface.dart';
import '../sangong_test_support.dart';

const _firstGroupID = '@Opaque_Group-A';
const _secondGroupID = 'G@Opaque_02';
final _groups = [
  GroupInfo.fromJson({'groupID': _firstGroupID, 'groupName': '第一群'}),
  GroupInfo.fromJson({'groupID': _secondGroupID, 'groupName': '第二群'}),
];

Future<void> _mount(WidgetTester tester, GroupFeatureStore store,
    {ValueChanged<SangongProfileEntryScope?>? observe}) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SangongProfileSurface(
              store: store,
              userID: 'target',
              loadGroups: () async => _groups,
              child: Builder(builder: (context) {
                observe?.call(SangongProfileEntryScope.maybeOf(context));
                return const SingleChildScrollView(
                    child: Column(children: [
                  Text('普通资料'),
                  SangongInlineProfilePanel(userID: 'target'),
                ]));
              })))));
  await flushSangong(tester);
}

void main() {
  setUp(() {
    OpenIM.iMManager.userID = 'owner';
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('revoking the viewing account closes the group chooser only',
      (tester) async {
    final privilege = FixtureAccountPrivilege();
    final api = SangongTestApi();
    final store = GroupFeatureStore(
        api: api,
        accountPrivilege: privilege,
        sessionCurrent: () => true,
        fetchGroups: (_) async => _groups);
    await _mount(tester, store);
    expect(privilege.refreshCount, 1);
    expect(api.calls, isEmpty);
    await tester.tap(find.text('选择游戏群'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('sangong-profile-group-chooser')),
        findsOneWidget);
    expect(find.text('第一群'), findsOneWidget);
    expect(privilege.refreshCount, 1);
    privilege.setAllowed(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('sangong-profile-group-chooser')),
        findsNothing);
    expect(find.text('选择游戏群'), findsNothing);
    expect(find.text('普通资料'), findsOneWidget);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    store.dispose();
  });

  testWidgets(
      'choosing a group preserves its opaque original ID without granting rights',
      (tester) async {
    final privilege = FixtureAccountPrivilege();
    final api = SangongTestApi()
      ..respond = (call) => {
            'groupID': _secondGroupID,
            'capabilityVersion': 1,
            'sangong': {'canManage': false, 'canConfigure': false},
          };
    final store = GroupFeatureStore(
        api: api,
        accountPrivilege: privilege,
        sessionCurrent: () => true,
        fetchGroups: (_) async => _groups);
    SangongProfileEntryScope? entry;
    await _mount(tester, store, observe: (value) => entry = value);
    expect(entry?.selectionContext?.currentUserID, 'owner');
    expect(entry?.selectionContext?.groupID, _firstGroupID);
    expect(entry?.selectionContext?.capabilities.sangong.canManage, isFalse);
    expect(api.calls, isEmpty);
    await tester.tap(find.text('选择游戏群'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二群'));
    await tester.pump(const Duration(milliseconds: 350));
    await flushSangong(tester);
    await tester.pumpAndSettle();
    expect(entry?.selectedGroupID, _secondGroupID);
    expect(entry?.onLedger, isNotNull);
    expect(api.calls.single.path,
        '/chat/groups/${Uri.encodeComponent(_secondGroupID)}/feature-capabilities');
    expect(find.text('没有当前群的三公配置或运营权限'), findsOneWidget);
    expect(find.text('普通资料'), findsOneWidget);
    expect(find.byKey(const ValueKey('sangong-profile-group-chooser')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    store.dispose();
  });
}
