import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/voice/voice_to_text_service.dart';
import 'package:openim/pages/chat/voice/widgets/voice_text_preview_dialog.dart';
import 'package:openim_common/openim_common.dart';

Finder _key(String name) => find.byKey(ValueKey('voice-text-$name'));

Future<void> _openPreview(
  WidgetTester tester,
  Future<String> Function(CancelToken) transcribe,
  void Function(VoiceTextChoice?) completed, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size size = const Size(375, 812),
  double keyboardInset = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  addTearDown(tester.view.reset);
  final previousDark = Styles.isDark;
  Styles.isDark = brightness == Brightness.dark;
  addTearDown(() => Styles.isDark = previousDark);
  Get.testMode = true;
  await tester.pumpWidget(GetMaterialApp(
    locale: const Locale('zh', 'CN'),
    translations: TranslationService(),
    theme: ThemeData(brightness: brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            completed(await VoiceTextPreviewDialog.show(
              context,
              transcribe: transcribe,
            ));
          },
          child: const Text('打开'),
        ),
      ),
    ),
  ));
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  await tester.tap(find.text('打开'));
  await tester.pump();
  // Recognition may remain pending indefinitely, so settle only the route.
  await tester.pump(const Duration(milliseconds: 350));
}

void _expectVisibleActions(WidgetTester tester, {required double bottom}) {
  final original = tester.getRect(_key('original'));
  final send = tester.getRect(_key('send'));
  final close = tester.getRect(_key('close'));
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final rect in [original, send, close]) {
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(width));
    expect(rect.top, greaterThanOrEqualTo(24));
    expect(rect.bottom, lessThanOrEqualTo(bottom + .01));
  }
  expect(original.overlaps(send), isFalse,
      reason: 'Both send choices must remain distinct at large text sizes');
  expect(_key('original').hitTestable(), findsOneWidget);
  expect(_key('send').hitTestable(), findsOneWidget);
  expect(_key('close').hitTestable(), findsOneWidget);
}

void main() {
  tearDown(Get.reset);

  testWidgets('show opens a bottom sheet and retains it during recognition',
      (tester) async {
    final pending = Completer<String>();
    late CancelToken request;
    var completed = 0;
    await _openPreview(tester, (token) {
      request = token;
      return pending.future;
    }, (_) => completed++);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.text('voiceTextPreview'.tr), findsOneWidget);
    expect(find.text('voiceToTextLoading'.tr), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('send')).onPressed, isNull);
    final sheet = tester.getRect(_key('sheet'));
    expect(sheet.center.dx, 375 / 2);
    expect(sheet.bottom, lessThanOrEqualTo(812));
    expect(sheet.bottom, greaterThanOrEqualTo(812 - 24));
    final close = tester.getRect(_key('close'));
    expect(close.center.dx, greaterThan(sheet.center.dx));
    expect(tester.widget<IconButton>(_key('close')).tooltip, StrRes.cancel);

    await tester.tapAt(Offset(20, sheet.top / 2));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.drag(_key('sheet'), const Offset(0, 240));
    await tester.pump(const Duration(milliseconds: 350));
    expect(_key('sheet'), findsOneWidget);
    expect(request.isCancelled, isFalse);
    expect(completed, 0);

    await tester.tap(_key('close'));
    await tester.pumpAndSettle();
    expect(request.isCancelled, isTrue);
    expect(completed, 1);
    pending.complete('关闭后到达的识别结果');
    await tester.pump();
    expect(find.byType(VoiceTextPreviewDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending original cancels recognition and ignores late text',
      (tester) async {
    final pending = Completer<String>();
    late CancelToken request;
    VoiceTextChoice? choice;
    await _openPreview(tester, (token) {
      request = token;
      return pending.future;
    }, (value) => choice = value);
    await tester.tap(_key('original'));
    await tester.pumpAndSettle();
    expect(request.isCancelled, isTrue);
    expect(choice?.sendOriginal, isTrue);
    pending.complete('晚到的识别结果');
    await tester.pump();
    expect(find.byType(VoiceTextPreviewDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edited text is trimmed and whitespace cannot be sent',
      (tester) async {
    var calls = 0;
    VoiceTextChoice? choice;
    await _openPreview(tester, (_) async {
      calls++;
      return '原始识别结果';
    }, (value) => choice = value);
    await tester.pumpAndSettle();
    await tester.enterText(_key('editor'), ' \n \t ');
    await tester.pump();
    expect(tester.widget<FilledButton>(_key('send')).onPressed, isNull);
    await tester.tap(_key('send'));
    await tester.pump();
    expect(choice, isNull);
    expect(_key('sheet'), findsOneWidget);
    expect(calls, 1);
    await tester.enterText(_key('editor'), '  修改后的文字  ');
    await tester.pump();
    await tester.tap(_key('send'));
    await tester.pumpAndSettle();
    expect(choice?.text, '修改后的文字');
    expect(choice?.sendOriginal, isFalse);
    expect(calls, 1);
  });

  testWidgets('empty recognition offers retry and never enables text sending',
      (tester) async {
    await _openPreview(tester, (_) async => ' \n ', (_) {});
    await tester.pumpAndSettle();
    expect(find.text('voiceToTextEmpty'.tr), findsOneWidget);
    expect(_key('retry'), findsOneWidget);
    expect(_key('editor'), findsNothing);
    expect(tester.widget<FilledButton>(_key('send')).onPressed, isNull);
    await tester.tap(_key('close'));
    await tester.pumpAndSettle();
  });

  testWidgets('rapid retry does not replace or duplicate an active request',
      (tester) async {
    final retryResult = Completer<String>();
    final requests = <CancelToken>[];
    await _openPreview(tester, (token) {
      requests.add(token);
      if (requests.length == 1) {
        return Future<String>.error(
            const VoiceToTextException('voiceToTextFailed'));
      }
      return retryResult.future;
    }, (_) {});
    await tester.pumpAndSettle();
    expect(find.text('voiceToTextFailed'.tr), findsOneWidget);
    final retry = tester.widget<TextButton>(_key('retry')).onPressed!;
    // Invoke a stale callback twice in one frame, before the loading UI rebuilds.
    retry();
    retry();
    await tester.pump();
    expect(requests, hasLength(2));
    expect(requests.last.isCancelled, isFalse);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('send')).onPressed, isNull);
    retryResult.complete('重试成功');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_key('editor')).controller!.text, '重试成功');
    expect(requests, hasLength(2));
    await tester.tap(_key('close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        '320px sheet fits large text, keyboard and long recognition / $dark',
        (tester) async {
      final pending = Completer<String>();
      var calls = 0;
      VoiceTextChoice? choice;
      const size = Size(320, 640);
      const keyboard = 220.0;
      final longText =
          List.filled(40, '下午三点在门口集合，我们先确认路线和时间，再一起出发。').join('\n');
      await _openPreview(tester, (_) {
        calls++;
        return pending.future;
      }, (value) => choice = value,
          brightness: dark ? Brightness.dark : Brightness.light,
          textScale: 2,
          size: size,
          keyboardInset: keyboard);
      expect(Theme.of(tester.element(_key('sheet'))).brightness,
          dark ? Brightness.dark : Brightness.light);
      _expectVisibleActions(tester, bottom: size.height - keyboard);
      expect(tester.takeException(), isNull);

      pending.complete(longText);
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextField>(_key('editor')).controller!.text, longText);
      _expectVisibleActions(tester, bottom: size.height - keyboard);
      final editor = tester.getRect(_key('editor'));
      expect(editor.width, lessThanOrEqualTo(size.width));
      expect(editor.height, greaterThan(0));
      expect(editor.height, lessThan(size.height - keyboard));
      expect(tester.takeException(), isNull);

      await tester.tap(_key('editor'));
      await tester.enterText(_key('editor'), '$longText\n最后确认一句。');
      await tester.pump();
      _expectVisibleActions(tester, bottom: size.height - keyboard);
      await tester.tap(_key('send'));
      await tester.pumpAndSettle();
      expect(choice?.text, '$longText\n最后确认一句。');
      expect(choice?.sendOriginal, isFalse);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '320px error sheet keeps retry and send choices reachable / $dark',
        (tester) async {
      await _openPreview(
          tester,
          (_) async => throw const VoiceToTextException('voiceToTextFailed'),
          (_) {},
          brightness: dark ? Brightness.dark : Brightness.light,
          textScale: 2,
          size: const Size(320, 640),
          keyboardInset: 220);
      await tester.pumpAndSettle();
      expect(find.text('voiceToTextFailed'.tr), findsOneWidget);
      expect(_key('retry').hitTestable(), findsOneWidget);
      _expectVisibleActions(tester, bottom: 420);
      expect(tester.widget<FilledButton>(_key('send')).onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.tap(_key('close'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('back navigation cancels the pending request', (tester) async {
    final pending = Completer<String>();
    late CancelToken request;
    await _openPreview(tester, (token) {
      request = token;
      return pending.future;
    }, (_) {});
    Navigator.of(tester.element(find.byType(VoiceTextPreviewDialog))).pop();
    await tester.pumpAndSettle();
    expect(request.isCancelled, isTrue);
    pending.complete('忽略');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid finish actions pop only the preview once', (tester) async {
    var completed = 0;
    VoiceTextChoice? choice;
    await _openPreview(tester, (_) async => '文字', (value) {
      completed++;
      choice = value;
    });
    await tester.pumpAndSettle();
    final original = tester.widget<TextButton>(_key('original')).onPressed!;
    final close = tester.widget<IconButton>(_key('close')).onPressed!;
    original();
    close();
    await tester.pumpAndSettle();
    expect(completed, 1);
    expect(choice?.sendOriginal, isTrue);
    expect(find.text('打开'), findsOneWidget);
    expect(find.byType(VoiceTextPreviewDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
