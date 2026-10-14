import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/search/contact_search_source.dart';
import 'package:get/get.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/contacts/select_contacts/selection/contact_single_selection.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/pages/contacts/select_contacts/group_list/group_list_view.dart';
import 'package:openim/pages/contacts/select_contacts/friend_list/friend_list_view.dart';
import 'package:openim/pages/group_features/sangong/configuration/sangong_config_selection_cell.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_my_config_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:openim_common/openim_common.dart';

import '../sangong_test_support.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Directory {
  final calls = <(ContactSingleSelectionKind, int)>[];
  FutureOr<List<SangongConfigSelection>> Function(
      ContactSingleSelectionKind, int)? respond;

  Future<List<GroupInfo>> groups() async => [
        for (final entry
            in await page(ContactSingleSelectionKind.groups, 0, 1000))
          GroupInfo(groupID: entry.id, groupName: entry.name, memberCount: 3),
      ];

  Future<List<ISUserInfo>> contacts() async => [
        for (final entry
            in await page(ContactSingleSelectionKind.contacts, 0, 1000))
          ISUserInfo.fromJson({'userID': entry.id, 'nickname': entry.name}),
      ];

  Future<List<SangongConfigSelection>> page(
      ContactSingleSelectionKind kind, int offset, int count) async {
    calls.add((kind, offset));
    if (respond != null) return await respond!(kind, offset);
    return kind == ContactSingleSelectionKind.groups
        ? const [
            SangongConfigSelection(id: '@settle-opaque', name: '结账测试群'),
            SangongConfigSelection(id: '@ledger-opaque', name: '通知测试群'),
          ]
        : const [
            // A legitimate SDK ID shaped like a public account must not be
            // resolved into another user's ID after selecting the contact.
            SangongConfigSelection(id: 'abcdefgh12', name: '记账机器人'),
          ];
  }
}

class _Accounts extends ContactSearchSource {
  final queries = <String>[];
  @override
  Future<List<UserFullInfo>?> users(String keyword, int page,
      {int? way}) async {
    queries.add(keyword);
    return [UserFullInfo(userID: 'manual-user-id', account: 'newaccount')];
  }
}

Future<void> _pumpConfig(WidgetTester tester, SangongRuntime runtime,
    _Directory source, _Accounts accounts,
    {bool dark = false, bool groupScoped = false}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(runtime.dispose);
  addTearDown(() => unmountSangong(tester));
  await pumpSangongPage(
      tester,
      runtime,
      Builder(
          builder: (context) => EasyLoading.init()(
              context,
              SangongMyConfigPage(
                groupScoped: groupScoped,
                initialGameGroupId: runtime.featureContext.groupID,
                loadGroups: source.groups,
                loadContacts: source.contacts,
                accountSearchSource: accounts,
              ))),
      dark: dark);
}

Future<void> _open(WidgetTester tester, String tooltip) async {
  final button = find.byTooltip(tooltip);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await flushSangong(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _choose(WidgetTester tester, String id) async {
  final group = find.byKey(ValueKey('select-group-$id'));
  await tester.tap(group.evaluate().isNotEmpty
      ? group
      : find.byKey(ValueKey('contact-card-friend-$id')));
  await tester.pumpAndSettle();
}

TextEditingController _input(WidgetTester tester, String label) => tester
    .widget<SangongConfigSelectionCell>(find.byWidgetPredicate((widget) =>
        widget is SangongConfigSelectionCell && widget.label == label))
    .controller;

void main() {
  setUp(() {
    OpenIM.iMManager.userID = 'owner';
    Get.put<AppController>(_App());
    Get.put<IMController>(_IM());
  });
  tearDown(() async => Get.reset());
  tearDown(() => EasyLoading.dismiss(animation: false));

  testWidgets('reused pages preserve another active selection controller',
      (tester) async {
    final existing = SelectContactsLogic.single(
        onPicked: (_) => fail('unrelated picker used'), isCurrent: () => true);
    Get.put<SelectContactsLogic>(existing);
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _pumpConfig(tester, runtime, _Directory(), _Accounts());
    await _open(tester, '从群聊列表选择报表群');
    expect(identical(Get.find<SelectContactsLogic>(), existing), isTrue);
    await _choose(tester, '@settle-opaque');
    await _open(tester, '从通讯录选择机器人');
    await _choose(tester, 'abcdefgh12');
    expect(identical(Get.find<SelectContactsLogic>(), existing), isTrue);
    expect(existing.isClosed, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'directory selections save opaque IDs in ${dark ? 'dark' : 'light'} theme',
        (tester) async {
      final api = SangongTestApi();
      final runtime = sangongTestRuntime(sangongTestContext(api));
      final directory = _Directory();
      final accounts = _Accounts();
      await _pumpConfig(tester, runtime, directory, accounts, dark: dark);
      expect(find.byTooltip('从群聊列表选择下注群'), findsNothing);
      await _open(tester, '从群聊列表选择报表群');
      expect(find.byType(SelectContactsFromGroupPage), findsOneWidget);
      await tester.enterText(find.byType(TextField), '结账');
      await tester.pump();
      expect(find.text('通知测试群'), findsNothing);
      await _choose(tester, '@settle-opaque');
      expect(_input(tester, '报表群').text, '@settle-opaque');
      expect(find.text('结账测试群'), findsOneWidget);
      await _open(tester, '从群聊列表选择上下分通知群');
      await _choose(tester, '@ledger-opaque');
      await _open(tester, '从通讯录选择机器人');
      expect(find.byType(SelectContactsFromFriendsPage), findsOneWidget);
      await _choose(tester, 'abcdefgh12');
      const hallName = ' \u0301\u{1F469}\u200D\u{1F680}厅名 ';
      final hallInput = tester.widget<TextField>(find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == '一号厅'));
      hallInput.controller!.text = hallName;
      await tester.tap(find.text('保存'));
      await flushSangong(tester);
      final write = api.calls.singleWhere((call) => call.method == 'PUT');
      expect(write.body?['name'], hallName);
      expect(write.body?['imGroupAdminStatsId'], '@settle-opaque');
      expect(write.body?['imGroupLedgerId'], '@ledger-opaque');
      expect(write.body?['imBotUserId'], 'abcdefgh12');
      expect(accounts.queries, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'cancel keeps drafts; editing a picked bot resolves the new account',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    final accounts = _Accounts();
    await _pumpConfig(tester, runtime, _Directory(), accounts);
    _input(tester, '报表群').text = '@manual-draft';
    await _open(tester, '从群聊列表选择报表群');
    await tester.tap(
        find.byIcon(Icons.arrow_back_ios_new_rounded).evaluate().isNotEmpty
            ? find.byIcon(Icons.arrow_back_ios_new_rounded)
            : find.byIcon(CupertinoIcons.back));
    await tester.pumpAndSettle();
    expect(_input(tester, '报表群').text, '@manual-draft');
    await _open(tester, '从通讯录选择机器人');
    await _choose(tester, 'abcdefgh12');
    _input(tester, '机器人').text = '@newaccount';
    await tester.pump();
    expect(find.text('记账机器人'), findsNothing);
    await tester.tap(find.text('保存'));
    await flushSangong(tester);
    expect(accounts.queries, ['@newaccount']);
    expect(
        api.calls
            .singleWhere((call) => call.method == 'PUT')
            .body?['imBotUserId'],
        'manual-user-id');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'current group stays fixed while its other bindings are selectable',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _pumpConfig(tester, runtime, _Directory(), _Accounts(),
        groupScoped: true);
    expect(find.byTooltip('从群聊列表选择下注群'), findsNothing);
    expect(_input(tester, '下注群').text, 'group-sangong');
    await _open(tester, '从群聊列表选择报表群');
    await _choose(tester, '@settle-opaque');
    expect(_input(tester, '报表群').text, '@settle-opaque');
    expect(_input(tester, '下注群').text, 'group-sangong');
    expect(api.calls.where((call) => call.method != 'GET'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'existing group page retries and searches the complete group list',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    final source = _Directory()
      ..respond = (_, __) => throw StateError('offline');
    await _pumpConfig(tester, runtime, source, _Accounts());
    await _open(tester, '从群聊列表选择报表群');
    expect(find.text('加载失败，请重试'), findsOneWidget);
    source.respond = (_, offset) => [
          ...List.generate(
              200, (i) => SangongConfigSelection(id: 'g-$i', name: 'Group $i')),
          const SangongConfigSelection(id: '@last-page', name: '最后一页的群')
        ];
    await tester.tap(find.text('重试'));
    await flushSangong(tester);
    await tester.enterText(find.byType(TextField), '最后一页');
    await tester.pump();
    expect(find.byType(SelectContactsFromGroupPage), findsOneWidget);
    await _choose(tester, '@last-page');
    expect(_input(tester, '报表群').text, '@last-page');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty contacts show an empty state and scope changes discard late data',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    final source = _Directory()..respond = (_, __) => [];
    await _pumpConfig(tester, runtime, source, _Accounts());
    await _open(tester, '从通讯录选择机器人');
    expect(find.text('暂无联系人'), findsOneWidget);
    await tester.tap(
        find.byIcon(Icons.arrow_back_ios_new_rounded).evaluate().isNotEmpty
            ? find.byIcon(Icons.arrow_back_ios_new_rounded)
            : find.byIcon(CupertinoIcons.back));
    await tester.pumpAndSettle();
    final pending = Completer<List<SangongConfigSelection>>();
    source.respond = (_, __) => pending.future;
    await _open(tester, '从通讯录选择机器人');
    runtime.updateContext(sangongTestContext(api,
        groupID: 'different-group', capabilityVersion: 2));
    pending
        .complete(const [SangongConfigSelection(id: 'old-bot', name: '失效联系人')]);
    await flushSangong(tester);
    expect(find.text('失效联系人'), findsNothing);
    expect(find.byType(ContactSingleSelection), findsNothing);
    expect(api.calls.where((call) => call.method != 'GET'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
