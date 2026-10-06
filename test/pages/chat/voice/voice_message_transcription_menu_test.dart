import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/voice/voice_transcription_controller.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_attachment_view.dart';

void main() {
  setUp(() => OpenIM.iMManager.userID = 'me');
  tearDown(Get.reset);
  // Folding is relevant only when the result exceeds the three-line preview.
  const transcript = '这是一条语音消息。\n第二行是转写内容。\n第三行继续保留内容。\n第四行用于验证折叠。';

  for (final dark in [false, true]) {
    for (final outgoing in [false, true]) {
      testWidgets(
          'private voice long press transcribes dark=$dark outgoing=$outgoing',
          (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Styles.isDark = dark;
        addTearDown(() => Styles.isDark = false);
        final message = Message.fromJson({
          'clientMsgID': 'private-voice',
          'contentType': MessageType.voice,
          'sendTime': 100000,
          'sendID': outgoing ? 'me' : 'other',
          'sessionType': 1,
          'isRead': false,
          'status': MessageStatus.succeeded,
          'attachedInfoElem': {'isPrivateChat': true, 'burnDuration': 30},
          'soundElem': {'duration': 6},
        });
        final answer = Completer<String>();
        var requests = 0;
        var writes = 0;
        final controller = VoiceTranscriptionController(
          transcribe: (Message received, {CancelToken? cancelToken}) {
            expect(received, same(message));
            requests++;
            return answer.future;
          },
          persist: (_, __) async => writes++,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
            translations: TranslationService(),
            locale: const Locale('zh', 'CN'),
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(dark ? 2 : 1),
                disableAnimations: dark,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: ListenableBuilder(
                listenable: controller,
                builder: (_, __) {
                  final state = controller.stateFor(message);
                  return ChatItemView(
                    message: message,
                    rightNickname: 'Me',
                    rightFaceUrl: '',
                    leftNickname: 'Sender',
                    leftFaceUrl: '',
                    showLeftNickname: false,
                    onTapUserProfile: (_) {},
                    voiceTranscription:
                        state.loading || state.hasText || state.error != null
                            ? state
                            : null,
                    onToggleVoiceTranscription: () =>
                        controller.toggle(message),
                    messageMenus: [
                      if (controller.canTranscribe(message) &&
                          !state.loading &&
                          !state.hasText)
                        PopMenuInfo(
                          text: 'voiceToText'.tr,
                          onTap: () => controller.transcribe(message),
                        ),
                      PopMenuInfo(text: '删除', onTap: () {}),
                    ],
                  );
                },
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('阅后即焚'), findsOneWidget);
        await tester.longPress(find.byType(ChatVoiceMessageView));
        await tester.pumpAndSettle();
        expect(find.text('转文字'), findsOneWidget);
        await tester.tap(find.text('转文字'));
        await tester.pump();
        expect(requests, 1);
        expect(find.text('转文字中…'), findsOneWidget);
        answer.complete(transcript);
        await tester.pumpAndSettle();
        expect(find.text(transcript), findsOneWidget);
        expect(find.byType(SelectableText), findsNothing);
        expect(writes, 0);
        expect(message.localEx, isNull);
        expect(find.text('收起文字'), findsOneWidget);
        await tester.tap(find.text('收起文字'));
        await tester.pumpAndSettle();
        expect(find.text('展开文字'), findsOneWidget);
        expect(writes, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
