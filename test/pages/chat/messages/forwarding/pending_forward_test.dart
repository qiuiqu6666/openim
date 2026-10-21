import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/forwarding/pending_forward.dart';
import 'package:openim/pages/chat/messages/forwarding/pending_forward_bar.dart';
import 'package:openim_common/openim_common.dart';

import 'support/chat_forwarding_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pending merged forward retains the source title', () async {
    final fixture = ForwardingFixture();
    addTearDown(fixture.dispose);
    expect(
        await fixture.controller.sendPending(
            [forwardingSource('one')], UserInfo(userID: 'target'),
            merged: true, mergeTitle: 'Source history'),
        isTrue);
    expect(fixture.merges.single.title, 'Source history');
  });

  test('partial pending sends request review instead of silently retrying',
      () async {
    final fixture = ForwardingFixture();
    addTearDown(fixture.dispose);
    fixture.onCreate = (message) async {
      if (message.clientMsgID == 'two') throw StateError('cannot create');
      return forwardingSource('forward-one', status: MessageStatus.sending);
    };
    expect(
        await fixture.controller.sendPending([
          forwardingSource('one'),
          forwardingSource('two')
        ], UserInfo(userID: 'target'), merged: false),
        isFalse);
    expect(fixture.sends, hasLength(1));
    expect(fixture.reviewRequests, 1);
  });

  test('selecting one recipient stages without sending, then send skips picker',
      () async {
    PendingForward? staged;
    final source =
        ForwardingFixture(stageForward: (messages, recipient, merged) async {
      staged = PendingForward(messages, recipient, merged: merged);
      return true;
    });
    final destination = ForwardingFixture();
    addTearDown(source.dispose);
    addTearDown(destination.dispose);
    expect(
        await source.forward([forwardingSource('one')], merged: false), isTrue);
    expect(source.sends, isEmpty);
    source.dispose();
    expect(
        await destination.controller.sendPending(
            staged!.messages, staged!.recipient,
            merged: staged!.merged),
        isTrue);
    expect(destination.pickerDescriptions, isEmpty);
    expect(destination.sends, hasLength(1));
  });

  test('pending send rejects repeat taps and keeps failed draft for retry',
      () async {
    final controller = PendingForwardController();
    final draft = PendingForward(
        [forwardingSource('one')], UserInfo(userID: 'target'),
        merged: false);
    controller.draft.value = draft;
    final receipt = Completer<bool>();
    final sending = controller.send((_) => receipt.future);
    expect(await controller.send((_) async => true), isFalse);
    controller.cancel();
    expect(controller.draft.value, same(draft));
    receipt.complete(false);
    expect(await sending, isFalse);
    expect(controller.draft.value, same(draft));
    expect(controller.sending.value, isFalse);
    expect(await controller.send((_) async => true), isTrue);
    expect(controller.draft.value, isNull);
  });

  for (final language in [
    (const Locale('zh', 'CN'), '你希望对转发的消息做什么？', '打开转发选项'),
    (const Locale('zh', 'TW'), '你希望對轉發的訊息做什麼？', '開啟轉發選項'),
    (
      const Locale('en', 'US'),
      'What would you like to do with the forwarded messages?',
      'Open forwarding options'
    ),
  ]) {
    testWidgets(
        'forward prompt survives stale translation registry ${language.$1}',
        (tester) async {
      await tester.pumpWidget(GetMaterialApp(
        locale: language.$1,
        translations: TranslationService(),
        home: Scaffold(body: PendingForwardBar(count: 1, onCancel: () {})),
      ));
      await tester.pumpAndSettle();
      Get.clearTranslations();
      addTearDown(() => Get.addTranslations(TranslationService().keys));
      await tester.tap(find.byKey(const ValueKey('pending-forward-cancel')));
      await tester.pumpAndSettle();
      expect(find.text(language.$2), findsOneWidget);
      expect(find.text(language.$3), findsOneWidget);
      expect(find.text('chatForwardClosePrompt'), findsNothing);
      expect(find.text('chatOpenForwardOptions'), findsNothing);
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
        'forward composer sends empty text and cancels without losing text / $dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final input = TextEditingController();
      var pending = true;
      var openedOptions = 0;
      String? sent;
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                    body: MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(2)),
                      child: Column(children: [
                        const Spacer(),
                        if (pending)
                          PendingForwardBar(
                              count: 30,
                              onOpenOptions: () => openedOptions++,
                              onCancel: () => setState(() => pending = false)),
                        ChatInputBox(
                          controller: input,
                          pendingSend: pending,
                          onSend: (text) => sent = text,
                          toolbox: const SizedBox(),
                          voiceRecordBar: const SizedBox(),
                        ),
                      ]),
                    ),
                  )),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('转发30条消息'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final send = find.widgetWithText(ElevatedButton, '发送');
      expect(send, findsOneWidget);
      await tester.tap(send);
      expect(sent, '');
      input.text = '附加文字';
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pending-forward-cancel')));
      await tester.pumpAndSettle();
      expect(pending, isTrue);
      expect(find.text('你希望对转发的消息做什么？'), findsOneWidget);
      await tester.tap(find.text('打开转发选项'));
      await tester.pumpAndSettle();
      expect(openedOptions, 1);
      expect(pending, isTrue);
      await tester.tap(find.byKey(const ValueKey('pending-forward-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消转发').last);
      await tester.pumpAndSettle();
      expect(pending, isFalse);
      expect(input.text, '附加文字');
      expect(find.widgetWithText(ElevatedButton, '发送'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      input.dispose();
    });
  }
}
