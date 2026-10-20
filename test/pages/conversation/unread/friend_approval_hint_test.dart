import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  tearDown(Get.reset);
  for (final brightness in Brightness.values) {
    for (final sender in ['self', 'peer']) {
      testWidgets('approval text renders for $sender in $brightness',
          (tester) async {
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
            translations: TranslationService(),
            locale: const Locale('zh', 'CN'),
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: ChatHintTextView(
                message: Message(
                    sendID: sender,
                    contentType:
                        MessageType.friendApplicationApprovedNotification,
                    notificationElem: NotificationElem(detail: '{}')),
                onTapUserProfile: (_) {},
              ),
            ),
          ),
        ));
        expect(find.text('你们已成为好友，可以开始聊天了'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
