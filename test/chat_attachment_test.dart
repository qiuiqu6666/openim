import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_attachment_view.dart';

void main() {
  setUp(() { OpenIM.iMManager.userID = 'me'; });
  test('all protocol call outcomes retain call type and text', () {
    for (final type in ['audio', 'video']) {
      for (final state in ['hangup', 'beHangup', 'cancel', 'beCanceled', 'reject', 'beRejected', 'timeout', 'networkError']) {
        final message = Message.fromJson({'contentType': MessageType.custom,
          'customElem': {'data': jsonEncode({'customType': 901, 'data': {'type': type, 'state': state, 'duration': 65}})}});
        final parsed = IMUtils.parseCustomMessage(message);
        expect(parsed?['type'], type);
        expect(parsed?['content'], isNotEmpty);
      }
    }
  });
  for (final dark in [false, true]) {
    for (final outgoing in [false, true]) {
      for (final group in [false, true]) {
        testWidgets('attachment dispatch and layout dark=$dark outgoing=$outgoing group=$group', (tester) async {
          Styles.isDark = dark;
          addTearDown(() => Styles.isDark = false);
          tester.view.physicalSize = const Size(320, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          Message message(int type, Map<String, dynamic> data) => Message.fromJson({
            'clientMsgID': '$type', 'contentType': type, 'sendTime': 100000,
            'sendID': outgoing ? OpenIM.iMManager.userID : 'other',
            'sessionType': group ? 3 : 1, 'isRead': false, 'status': 2,
            ...data,
          });
          final messages = [
            message(MessageType.file, {'fileElem': {'fileName': 'a_very_long_filename_without_spaces_123456789012345678901234567890.pdf', 'fileSize': 2048}}),
            message(MessageType.voice, {'soundElem': {'duration': 60}}),
            message(MessageType.custom, {'customElem': {'data': jsonEncode({'customType': 901, 'data': {'type': 'audio', 'state': 'hangup', 'duration': 65}})}}),
          ];
          await tester.pumpWidget(ScreenUtilInit(designSize: const Size(375, 812),
            builder: (_, __) => MaterialApp(theme: dark ? ThemeData.dark() : ThemeData.light(),
              builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
              home: Scaffold(body: SingleChildScrollView(child: Column(children: messages.map((message) => ChatItemView(
                message: message, rightNickname: 'Me', rightFaceUrl: '', leftNickname: 'Sender',
                showLeftNickname: group, onTapUserProfile: (_) {},
                customTypeBuilder: (_, message) { final data = IMUtils.parseCustomMessage(message)!;
                  return CustomTypeInfo(ChatCallItemView(type: data['type'], content: data['content'])); },
              )).toList()))))));
          await tester.pumpAndSettle();
          expect(find.byType(ChatFileMessageView), findsOneWidget);
          expect(find.byType(ChatVoiceMessageView), findsOneWidget);
          expect(find.byType(ChatCallItemView), findsOneWidget);
          expect(find.text(StrRes.unsupportedMessage), findsNothing);
          expect(tester.takeException(), isNull);
          for (final bubble in find.byType(ChatBubble).evaluate()) {
            final rect = tester.getRect(find.byWidget(bubble.widget));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(320));
          }
        });
      }
    }
  }
}


