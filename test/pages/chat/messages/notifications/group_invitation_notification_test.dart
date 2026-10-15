import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final scenario in ['approval', 'self invitation', 'legacy']) {
    testWidgets('group invitation uses actual inviter: $scenario', (tester) async {
      OpenIM.iMManager.userID = 'approver';
      Get.locale = const Locale('zh', 'CN');
      final inviterID = scenario == 'self invitation' ? 'approver' : 'inviter';
      final message = Message.fromJson({
        'contentType': MessageType.memberInvitedNotification,
        'groupID': 'group',
        'notificationElem': {
          'detail': jsonEncode({
            'opUser': {'userID': 'approver', 'nickname': '审批人'},
            if (scenario != 'legacy')
              'inviterUser': {'userID': inviterID, 'nickname': '真实邀请人'},
            'invitedUserList': [
              {'userID': 'member', 'nickname': '上古大神'},
            ],
          }),
        },
      });
      String? tappedID;
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          home: Scaffold(
            body: ChatHintTextView(
              message: message,
              onTapUserProfile: (user) => tappedID = user.userID,
            ),
          ),
        ),
      ));
      final expectedName = scenario == 'approval' ? '真实邀请人' : '你';
      final expected = '$expectedName 邀请 上古大神 加入群聊';
      expect(IMUtils.parseNtf(message), expected);
      final richText = tester.widgetList<RichText>(find.byType(RichText))
          .singleWhere((widget) => widget.text.toPlainText() == expected);
      final spans = (richText.text as TextSpan).children!.cast<TextSpan>();
      final inviterSpan = spans.firstWhere((span) => span.text == expectedName);
      (inviterSpan.recognizer as TapGestureRecognizer).onTap!();
      expect(tappedID, scenario == 'legacy' ? 'approver' : inviterID);
      expect(tester.takeException(), isNull);
    });
  }
}
