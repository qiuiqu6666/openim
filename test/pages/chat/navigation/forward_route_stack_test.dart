import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/forwarding/pending_forward.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim/routes/app_pages.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const sdk = MethodChannel('flutter_openim_sdk');

  for (final group in [false, true]) {
    testWidgets('repeated forwards return directly home (group: $group)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SpUtil().init();
      OpenIM.iMManager.userID = '';
      Get.testMode = true;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(sdk,
          (call) async {
        if (call.method == 'getUsersInfo') return '[]';
        expect(call.method, 'getOneConversation');
        final id = (call.arguments as Map)['sourceID'] as String;
        return jsonEncode(ConversationInfo(
          conversationID: 'conversation-$id',
          conversationType:
              group ? ConversationType.superGroup : ConversationType.single,
          userID: group ? null : id,
          groupID: group ? id : null,
        ).toJson());
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(sdk, null);
        Get.reset();
        while (GetTags.chat != null) {
          GetTags.destroyChatTag();
        }
      });
      PendingForward? received;
      await tester.pumpWidget(GetMaterialApp(
        initialRoute: AppRoutes.home,
        getPages: [
          GetPage(
              name: AppRoutes.home, page: () => const Text('conversations')),
          GetPage(name: '/source', page: () => const Text('source')),
          GetPage(name: '/picker', page: () => const Text('picker')),
          GetPage(
              name: AppRoutes.chat,
              page: () {
                received = Get.arguments['pendingForward'] as PendingForward;
                return const Text('destination');
              }),
        ],
      ));
      await tester.pumpAndSettle();
      Get.toNamed('/source');
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        Get.toNamed('/picker');
        await tester.pumpAndSettle();
        final pending = PendingForward(
          [Message(clientMsgID: 'message-$i')],
          group
              ? GroupInfo(groupID: 'target-$i')
              : UserInfo(userID: 'target-$i'),
          merged: i.isOdd,
        );
        expect(await AppNavigator.stageForward(pending, isCurrent: () => true),
            isTrue);
        await tester.pumpAndSettle();
        expect(Get.currentRoute, AppRoutes.chat);
        expect(received, same(pending));
      }
      Get.back<void>();
      await tester.pumpAndSettle();
      expect(Get.currentRoute, AppRoutes.home);
      expect(find.text('conversations'), findsOneWidget);
      expect(Get.key.currentState!.canPop(), isFalse);
    });
  }
}
