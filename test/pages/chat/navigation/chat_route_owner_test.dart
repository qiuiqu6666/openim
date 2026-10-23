import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/chat_view.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim/widgets/theme_aware_page.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim/pages/chat/group_setup/group_setup_view.dart';
import 'package:openim/pages/chat/chat_setup/chat_setup_logic.dart';
import 'package:openim/pages/chat/chat_setup/chat_setup_view.dart';
import 'package:openim/pages/chat/group_setup/edit_name/edit_name_logic.dart';
import 'package:openim/pages/chat/group_setup/edit_name/edit_name_view.dart';

class _Group extends GetxController implements GroupSetupLogic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Setup extends GetxController implements ChatSetupLogic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Editor extends GetxController implements EditGroupNameLogic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Chat extends GetxController implements ChatLogic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'secondary routes retain owners when theme rebuilds after cleanup',
      (tester) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    Get.put<GroupSetupLogic>(_Group());
    Get.put<ChatSetupLogic>(_Setup());
    Get.put<EditGroupNameLogic>(_Editor());
    final wrappers = AppPages.routes
        .where((p) => [
              AppRoutes.groupChatSetup,
              AppRoutes.chatSetup,
              AppRoutes.editGroupName
            ].contains(p.name))
        .map((p) => p.page() as ThemeAwarePage)
        .toList();
    final before = <Widget>[];
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      before.addAll(wrappers.map((w) => w.builder(context)));
      return const SizedBox();
    })));
    expect(before.whereType<GroupSetupPage>(), hasLength(1));
    expect(before.whereType<ChatSetupPage>(), hasLength(1));
    expect(before.whereType<EditGroupNamePage>(), hasLength(1));
    await Get.delete<GroupSetupLogic>();
    await Get.delete<ChatSetupLogic>();
    await Get.delete<EditGroupNameLogic>();
    final after = <Widget>[];
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(builder: (context) {
          after.addAll(wrappers.map((w) => w.builder(context)));
          return const SizedBox();
        })));
    expect(tester.takeException(), isNull);
    for (var i = 0; i < before.length; i++) {
      expect(after[i], same(before[i]));
    }
  });
  testWidgets('an older chat route keeps its owner when another chat opens',
      (tester) async {
    Get.testMode = true;
    addTearDown(() async {
      Get.reset();
      while (GetTags.chat != null) {
        GetTags.destroyChatTag();
      }
    });
    GetTags.createChatTag();
    final first = Get.put<ChatLogic>(_Chat(), tag: GetTags.chat);
    final route = AppPages.routes.firstWhere((p) => p.name == AppRoutes.chat);
    final wrapper = route.page() as ThemeAwarePage;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    GetTags.createChatTag();
    // A separate tag also represents the chat opened after switching accounts.
    final second = Get.put<ChatLogic>(_Chat(), tag: GetTags.chat);
    ChatPage? before, after;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      before = wrapper.builder(context) as ChatPage;
      return const SizedBox();
    })));
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(builder: (context) {
          after = wrapper.builder(context) as ChatPage;
          return const SizedBox();
        })));
    expect(before!.logic, same(first));
    expect(after!.logic, same(first));
    expect(after!.logic, isNot(same(second)));
    expect(after, same(before));
  });
}
