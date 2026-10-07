import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_panel.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_authorized_view.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_message_actions.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_surface.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_ledger.dart';
import 'sangong_test_support.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_ledger_floating_entry.dart';

dynamic profileResponse(SangongCall call) {
  if (call.path.endsWith('/users')) {
    return {
      'users': [
        {
          'userId': 19,
          'imUserId': 'im_target',
          'balance': 420,
          'rebatePer10000': 8
        }
      ],
      'total': 1,
      'nextBeforeId': 0
    };
  }
  if (call.path.endsWith('/user')) {
    return {
      'exists': true,
      'user': {
        'userId': 19,
        'imUserId': 'im_target',
        'balance': 420,
        'rebatePer10000': 8
      },
      'parent': {'nickname': '上级甲'}
    };
  }
  if (call.path.endsWith('/commands/wallet.adjust')) {
    return sangongReceipt(call, {'imUserId': 'im_target', 'balance': 430});
  }
  return sangongFixtureResponse(call);
}

void main() {
  setUp(() {
    OpenIM.iMManager.userID = 'owner';
    SharedPreferences.setMockInitialValues({});
  });
  for (final size in [const Size(320, 700), const Size(1200, 900)]) {
    testWidgets('profile surface actual entry and revoke at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = SangongTestApi()
        ..respond = (call) {
          if (call.path.endsWith('/feature-capabilities')) {
            return {
              'groupID': 'g',
              'capabilityVersion': 1,
              'sangong': {'canManage': true, 'tenantID': 'tenant-authorized'}
            };
          }
          if (call.path.endsWith('/user-report')) {
            return sangongUserReport(imUserId: 'im_target');
          }
          if (call.path.endsWith('/sessions')) return {'sessions': []};
          if (call.path.endsWith('/user-hierarchy')) return {'members': []};
          return profileResponse(call);
        };
      final group = GroupInfo.fromJson({
        'groupID': 'g',
        'groupName': '游戏群',
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
      final store = GroupFeatureStore(
          accountPrivilege: FixtureAccountPrivilege(),
          api: api,
          sessionCurrent: () => true,
          fetchGroups: (_) async => [group]);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SangongProfileSurface(
                  store: store,
                  loadGroups: () async => [group],
                  userID: 'im_target',
                  child: const SingleChildScrollView(
                      child: Column(children: [
                    Text('个人资料'),
                    SangongInlineProfilePanel(userID: 'im_target')
                  ]))))));
      await flushSangong(tester);
      await flushSangong(tester);
      expect(find.text('个人资料'), findsOneWidget);
      expect(find.textContaining('当前积分 420'), findsWidgets);
      if (size.width < 900) {
        expect(find.byType(SangongProfileLedgerFloatingEntry), findsOneWidget);
        expect(
            tester
                .widget<SangongProfileLedgerFloatingEntry>(
                    find.byType(SangongProfileLedgerFloatingEntry))
                .onOpenLedger,
            isNotNull);
        await tester.tap(find.descendant(
            of: find.byType(SangongProfileLedgerFloatingEntry),
            matching: find.byType(InkWell)));
        await tester.pump(const Duration(milliseconds: 350));
        await flushSangong(tester);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byType(SangongProfileLedger), findsOneWidget);
        await tester.drag(find.byType(NestedScrollView), const Offset(0, -440));
        await tester.pumpAndSettle();
        expect(find.text('下注流水'), findsOneWidget);
        expect(find.text('上下分'), findsWidgets);
      }
      expect(tester.takeException(), isNull);
      store.invalidateCapabilities('g');
      await tester.pump();
      expect(find.textContaining('当前积分 420'), findsNothing);
      if (size.width < 900) expect(find.text('下注流水'), findsNothing);
      await unmountSangong(tester);
      store.dispose();
    });
  }
  for (final dark in [false, true]) {
    testWidgets('profile real data, 320 wide, dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = SangongTestApi()..respond = profileResponse;
      final runtime = sangongTestRuntime(sangongTestContext(api));
      await pumpSangongPage(
          tester,
          runtime,
          const Scaffold(
              body: SingleChildScrollView(
                  child: SangongProfilePanel(userID: 'im_target'))),
          dark: dark);
      expect(find.textContaining('当前积分 420'), findsOneWidget);
      expect(find.textContaining(' · 上级 上级甲'), findsOneWidget);
      expect(find.text('上分'), findsOneWidget);
      expect(find.text('定庄'), findsOneWidget);
      expect(
          api.calls.every((c) =>
              c.headers?['X-Tenant-Id'] == expectedSangongRequestTenant()),
          isTrue);
      expect(tester.takeException(), isNull);
      await unmountSangong(tester);
      runtime.dispose();
    });
  }
  testWidgets('credit requires confirmation and uses original IM identity',
      (tester) async {
    final api = SangongTestApi()..respond = profileResponse;
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await pumpSangongPage(tester, runtime,
        const Scaffold(body: SangongProfilePanel(userID: 'im_target')));
    await tester.enterText(find.byType(TextField).first, '10');
    await tester.tap(find.text('上分'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.count('/commands/wallet.adjust'), 0);
    await tester.tap(find.text('确认'));
    await flushSangong(tester);
    expect(api.count('/commands/wallet.adjust'), 1);
    final request =
        api.calls.firstWhere((c) => c.path.endsWith('/commands/wallet.adjust'));
    expect(request.body?['input']['imUserId'], 'im_target');
    expect(request.body?['input']['delta'], 10);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });
  testWidgets('late response after revocation cannot expose private content',
      (tester) async {
    final response = Completer<dynamic>();
    final api = SangongTestApi()
      ..respond = (call) =>
          call.path.endsWith('/user') ? response.future : profileResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await pumpSangongPage(tester, runtime,
        const Scaffold(body: SangongProfilePanel(userID: 'im_target')));
    runtime.updateContext(
        sangongTestContext(api, canManage: false, capabilityVersion: 2));
    response.complete({
      'users': [
        {'imUserId': 'im_target', 'balance': 420}
      ]
    });
    await flushSangong(tester);
    expect(find.textContaining('当前积分 420'), findsNothing);
    expect(find.text('上分'), findsNothing);
    await unmountSangong(tester);
    runtime.dispose();
  });
  testWidgets('covered ledger hides on revoke and dispose', (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await pumpSangongPage(
        tester,
        runtime,
        Scaffold(
            body: SangongAuthorizedView(
                runtime: runtime, child: const Text('private ledger'))));
    expect(find.text('private ledger'), findsOneWidget);
    runtime.dispose();
    await tester.pump();
    expect(find.text('private ledger'), findsNothing);
    await unmountSangong(tester);
  });
  testWidgets('message menus require permissions and real cutoff identity',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    List<PopMenuInfo> menus = [];
    final message = Message.fromJson({
      'groupID': 'group-sangong',
      'sendID': 'im_target',
      'status': MessageStatus.succeeded,
      'contentType': MessageType.text,
      'clientMsgID': '123456',
      'seq': 20,
      'textElem': {'content': '2.5000'}
    });
    await pumpSangongPage(tester, runtime, Builder(builder: (context) {
      menus = SangongMessageActions.items(context, message);
      return const SizedBox();
    }));
    expect(menus.map((m) => m.id),
        containsAll(['sangong_stats', 'sangong_banker']));
    expect(menus.map((m) => m.id), contains('sangong_exclude'));
    runtime.updateContext(
        sangongTestContext(api, canManage: false, capabilityVersion: 2));
    await tester.pump();
    expect(menus, isEmpty);
    await unmountSangong(tester);
    runtime.dispose();
  });
}
