import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/chat/chat_setup/chat_setup_logic.dart';
import 'package:openim/pages/chat/chat_setup/chat_setup_view.dart';
class FakeSetup extends GetxController implements ChatSetupLogic {
  @override
  final conversationInfo = ConversationInfo(conversationID: 'test', showName: '好友昵称').obs;
  @override
  final updating = false.obs;
  @override
  bool get isPinned => false;
  @override
  bool get isMuted => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
  testWidgets('chat settings renders reference sections on narrow screen', (tester) async {
    tester.view.physicalSize = const Size(375,812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(Get.reset);
    Get.put<ChatSetupLogic>(FakeSetup());
    await tester.pumpWidget(ScreenUtilInit(designSize: const Size(375,812), builder: (_,__) => GetMaterialApp(
      translations: TranslationService(), locale: const Locale('zh','CN'), home: ChatSetupPage())));
    await tester.pumpAndSettle();
    expect(find.text('聊天设置'), findsOneWidget);
    expect(find.text('查找聊天内容'), findsOneWidget);
    expect(find.text('设置当前聊天背景'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
