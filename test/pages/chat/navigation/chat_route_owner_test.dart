import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/chat_view.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim/widgets/theme_aware_page.dart';
import 'package:openim_common/openim_common.dart';

class _Chat extends GetxController implements ChatLogic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
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
