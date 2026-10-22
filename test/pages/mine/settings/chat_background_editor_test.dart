import 'package:flutter/material.dart';
import 'package:openim/pages/mine/settings/appearance/chat_background/chat_background_preview.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/chat_background_page.dart';
import 'package:openim/pages/mine/settings/chat_background_local_service.dart';
import 'package:openim/pages/mine/settings/appearance/chat_background/chat_background_menu_tokens.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = 'background-test';
  });

  for (final dark in [false, true]) {
    testWidgets('scope, inline selection, inheritance and clear dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await ChatBackgroundLocalService.saveValue(
          ChatBackgroundLocalService.globalConversationId, 'color:ffbedbff');
      await tester.pumpWidget(MaterialApp(
          builder: EasyLoading.init(),
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: const ChatBackgroundPage(
              conversationId: 'test-chat', conversationName: 'Alice')));
      await tester.pumpAndSettle();
      expect(find.text('Using global default'), findsOneWidget);
      // Lock the reference geometry rather than only checking that controls exist.
      final previewStack = find
          .descendant(
              of: find.byType(ChatBackgroundPreview),
              matching: find.byType(Stack))
          .first;
      // 168 outer height minus the two 0.6 borders.
      expect(tester.getSize(previewStack).height, closeTo(166.8, 0.01));
      final scopeControl = find
          .ancestor(
              of: find.text('This Chat'),
              matching: find.byType(GestureDetector))
          .first;
      expect(tester.getSize(scopeControl).height, 36);
      final previewBubble =
          tester.widget<Text>(find.text('Hi, let’s talk tonight.'));
      expect(previewBubble.style!.fontSize, 14);
      await tester.tap(find.text('All Chats'));
      await tester.pumpAndSettle();
      expect(find.text('Global default preview'), findsOneWidget);
      await tester.tap(find.text('This Chat'));
      await tester.pumpAndSettle();
      final green = find.bySemanticsLabel('Light green');
      await tester.ensureVisible(green);
      await tester.tap(green);
      await tester.pumpAndSettle();
      expect(ChatBackgroundLocalService.direct('test-chat'), 'color:ffcfeccb');
      expect(ChatBackgroundLocalService.global(), 'color:ffbedbff');
      EasyLoading.dismiss(animation: false);
      await tester.pumpAndSettle();
      final clear = find.text('Clear This Chat Background');
      await Scrollable.ensureVisible(tester.element(clear), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(ChatBackgroundLocalService.direct('test-chat'), isNull);
      expect(
          ChatBackgroundLocalService.effective('test-chat'), 'color:ffbedbff');
      EasyLoading.dismiss(animation: false);
      await tester.pumpAndSettle();
      final picture = find.bySemanticsLabel('Mountain Meadow');
      await tester.scrollUntilVisible(picture, 300,
          scrollable: find.byType(Scrollable).first);
      await Scrollable.ensureVisible(tester.element(picture), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(picture);
      await tester.pumpAndSettle();
      expect(ChatBackgroundLocalService.direct('test-chat'),
          ChatBackgroundMenuTokens.options.last);
      expect(tester.takeException(), isNull);
      EasyLoading.dismiss(animation: false);
      await tester.pumpAndSettle();
    });

    testWidgets('small screen large text global entry dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!),
          home: const ChatBackgroundPage()));
      await tester.pumpAndSettle();
      expect(find.text('This Chat'), findsNothing);
      expect(find.text('Global Chat Background'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
          find.bySemanticsLabel('Mountain Meadow'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    });
  }
}
