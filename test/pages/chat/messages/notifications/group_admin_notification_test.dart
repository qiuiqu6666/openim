import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final appointed in [true, false]) {
    for (final currentUser in ['owner', 'member', 'observer']) {
      testWidgets('administrator tip appointed=$appointed viewer=$currentUser', (tester) async {
        OpenIM.iMManager.userID = currentUser;
        final message = Message.fromJson({
          'contentType': appointed
              ? MessageType.groupMemberSetToAdminNotification
              : MessageType.groupMemberSetToOrdinaryUserNotification,
          'groupID': 'group',
          'notificationElem': {'detail': jsonEncode({
            'opUser': {'userID': 'owner', 'nickname': '群主'},
            'changedUser': {'userID': 'member', 'nickname': '成员'},
          })},
        });
        String? tappedID;
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
            translations: TranslationService(),
            locale: const Locale('zh', 'CN'),
            home: Scaffold(body: ChatHintTextView(
              message: message,
              onTapUserProfile: (user) => tappedID = user.userID,
            )),
          ),
        ));
        final owner = currentUser == 'owner' ? '你' : '群主';
        final member = currentUser == 'member' ? '你' : '成员';
        final expected = appointed
            ? '$owner 将 $member 设为管理员'
            : '$owner 取消了 $member 的管理员身份';
        expect(IMUtils.parseNtf(message), expected);
        final richText = tester.widgetList<RichText>(find.byType(RichText))
            .singleWhere((widget) => widget.text.toPlainText() == expected);
        expect(richText.textAlign, TextAlign.center);
        final spans = (richText.text as TextSpan).children!.cast<TextSpan>();
        final names = spans.where((span) => span.recognizer != null).toList();
        (names.first.recognizer as TapGestureRecognizer).onTap!();
        expect(tappedID, 'owner');
        (names.last.recognizer as TapGestureRecognizer).onTap!();
        expect(tappedID, 'member');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
