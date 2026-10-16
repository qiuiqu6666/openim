import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/chat/group/identity/group_sender_avatars.dart';

Message invitation() => Message.fromJson({
      'groupID': 'group',
      'sendID': 'system',
      'contentType': MessageType.memberInvitedNotification,
      'notificationElem': {
        'detail': jsonEncode({
          'opUser': {'userID': 'approver', 'nickname': '审批人'},
          'inviterUser': {'userID': 'inviter', 'nickname': '葫芦娃'},
          'invitedUserList': [
            {'userID': 'member', 'nickname': '当当'},
          ],
          'extension': {'keep': true},
        }),
      },
    });

void main() {
  testWidgets('historical invitation refreshes both names and profile targets',
      (tester) async {
    OpenIM.iMManager.userID = 'me';
    final response = Completer<List<GroupMembersInfo>>();
    final requested = <String>[];
    final cache = GroupSenderAvatars(
      isCurrent: () => true,
      lookup: (ids) {
        requested.addAll(ids);
        return response.future;
      },
    );
    addTearDown(cache.close);
    final message = invitation();
    final original = message.notificationElem!.detail;
    cache.sync([message, message]);
    String? tappedID, tappedName;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        home: Scaffold(
          body: Obx(() => ChatHintTextView(
                message: cache.noticeFor(message),
                onTapUserProfile: (user) {
                  tappedID = user.userID;
                  tappedName = user.name;
                },
              )),
        ),
      ),
    ));
    expect(find.text('葫芦娃 邀请 当当 加入群聊', findRichText: true), findsOneWidget);
    response.complete([
      GroupMembersInfo(userID: 'inviter', nickname: '宫藏'),
      GroupMembersInfo(userID: 'member', nickname: '新当当'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(requested.toSet(), {'approver', 'inviter', 'member', 'system'});
    expect(requested.length, 4);
    final finder = find.text('宫藏 邀请 新当当 加入群聊', findRichText: true);
    expect(finder, findsOneWidget);
    final span = (tester.widget<RichText>(finder).text as TextSpan)
        .children!
        .cast<TextSpan>()
        .firstWhere((s) => s.text == '宫藏');
    (span.recognizer as TapGestureRecognizer).onTap!();
    expect(tappedID, 'inviter');
    expect(tappedName, '宫藏');
    cache.updateNickname('inviter', '再次改名');
    await tester.pump();
    expect(find.text('再次改名 邀请 新当当 加入群聊', findRichText: true), findsOneWidget);
    expect(message.notificationElem!.detail, original);
    final projected =
        jsonDecode(cache.noticeFor(message).notificationElem!.detail!);
    expect(projected['extension'], {'keep': true});
    expect(projected['opUser']['userID'], 'approver');
  });

  test('failed or missing member lookup preserves original notification',
      () async {
    final cache = GroupSenderAvatars(
      isCurrent: () => true,
      lookup: (_) async => throw StateError('offline'),
    );
    addTearDown(cache.close);
    final message = invitation();
    cache.sync([message]);
    await Future<void>.delayed(Duration.zero);
    expect(cache.noticeFor(message), same(message));
    final malformed = invitation()
      ..notificationElem = NotificationElem(detail: '{');
    cache.sync([malformed]);
    expect(cache.noticeFor(malformed), same(malformed));
  });
}
