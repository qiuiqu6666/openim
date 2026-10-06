import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history_search/widgets/chat_history_result_tile.dart';
import 'package:openim/pages/chat/media/widgets/chat_video_thumbnail.dart';
import 'package:openim_common/openim_common.dart';

Message _message({bool picture = false, bool expired = false}) =>
    Message.fromJson({
      'clientMsgID': 'summary-result',
      'contentType': picture ? MessageType.picture : MessageType.text,
      'sendID': 'sender-id',
      'senderNickname': '  很长的发送者昵称用来验证窄屏上的布局  ',
      'sendTime': DateTime(2024, 6, 15, 12).millisecondsSinceEpoch,
      'textElem': {
        'content': '很长的搜索消息摘要，用来确认两行文字在窄屏和大字号下依然可读，也能够点击打开原来的消息。',
      },
      if (picture)
        'pictureElem': {
          'sourcePath': '/private/should-not-read.jpg',
          'sourcePicture': {
            'url': 'https://example.invalid/should-not-fetch.jpg',
          },
        },
      if (expired)
        'attachedInfoElem': {
          'isPrivateChat': true,
          'burnDuration': 1,
          'hasReadTime': DateTime(2020).millisecondsSinceEpoch,
        },
    });

Future<void> _mount(WidgetTester tester, Message message,
    {Brightness brightness = Brightness.light,
    Size viewport = const Size(320, 844),
    VoidCallback? onTap}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      theme: ThemeData(brightness: brightness),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      translations: TranslationService(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ChatHistoryResultTile(message: message, onTap: onTap ?? () {}),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: long result fits 320px at 200% text',
        (tester) async {
      final message = _message();
      var taps = 0;
      await _mount(tester, message,
          brightness: brightness, onTap: () => taps++);
      final summary = find.text(message.textElem!.content!);
      expect(summary, findsOneWidget);
      expect(find.text(message.senderNickname!.trim()), findsOneWidget);
      expect(find.byType(AvatarView), findsOneWidget);
      final resultBounds = tester.getRect(find.byType(ChatHistoryResultTile));
      expect(resultBounds.left, greaterThanOrEqualTo(0));
      expect(resultBounds.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
      await tester.tap(summary);
      await tester.pump();
      expect(taps, 1);
      await _unmount(tester);
    });

    testWidgets('${brightness.name}: picture search result loads no thumbnail',
        (tester) async {
      var requests = 0;
      await HttpOverrides.runZoned(() async {
        await _mount(tester, _message(picture: true), brightness: brightness);
        expect(find.byType(AvatarView), findsOneWidget);
        expect(find.byType(ChatVideoThumbnail), findsNothing);
        expect(find.textContaining(StrRes.picture), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      }, createHttpClient: (_) {
        requests++;
        throw StateError('Search summaries must not fetch message media');
      });
      expect(requests, 0);
    });

    testWidgets('${brightness.name}: expired result never mounts content',
        (tester) async {
      var taps = 0;
      final message = _message(picture: true, expired: true)
        ..senderFaceUrl = 'https://example.invalid/private-avatar.jpg';
      var requests = 0;
      await HttpOverrides.runZoned(() async {
        await _mount(tester, message,
            brightness: brightness, onTap: () => taps++);
        expect(find.text('sdkExpired'.tr), findsOneWidget);
        expect(find.text(message.senderNickname!.trim()), findsNothing);
        expect(find.textContaining(StrRes.picture), findsNothing);
        expect(find.byType(AvatarView), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(find.byType(ChatVideoThumbnail), findsNothing);
        await tester.tap(find.text('sdkExpired'.tr), warnIfMissed: false);
        await tester.pump();
        expect(taps, 0);
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      }, createHttpClient: (_) {
        requests++;
        throw StateError('Expired content must not load an avatar or media');
      });
      expect(requests, 0);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 375.0]) {
      testWidgets(
          '${platform.name}: ${width.toInt()}px phone keeps row geometry when viewport height shrinks',
          (tester) async {
        final message = _message();
        await _mount(tester, message, viewport: Size(width, 844));
        final tile = find.byType(ChatHistoryResultTile);
        final avatar = find.byType(AvatarView);
        final summary = find.text(message.textElem!.content!);
        final originalElement = tester.element(tile);
        final originalRowBounds = tester.getRect(tile);
        final originalAvatarBounds = tester.getRect(avatar);
        final originalSummaryBounds = tester.getRect(summary);
        expect(originalAvatarBounds.size, const Size(44, 44));
        expect(find.byType(SelectionArea), findsNothing);
        expect(tester.takeException(), isNull);

        for (final height in [300.0, 200.0, 844.0]) {
          // Native phone viewport changes can become wider than tall while a
          // keyboard or orientation change leaves the same narrow row width.
          tester.view.physicalSize = Size(width, height);
          await tester.pumpAndSettle();
          expect(tester.element(tile), same(originalElement));
          expect(tester.getRect(avatar), originalAvatarBounds,
              reason: 'A phone avatar must not become a desktop avatar.');
          expect(tester.getRect(tile), originalRowBounds,
              reason: 'Reducing available height must not change row height.');
          expect(tester.getRect(summary), originalSummaryBounds);
          expect(find.byType(SelectionArea), findsNothing,
              reason: 'A narrow native phone must retain mobile interactions.');
          expect(tester.takeException(), isNull);
        }
        await _unmount(tester);
      }, variant: TargetPlatformVariant({platform}));
    }
  }

  testWidgets('private result unloads its avatar and summary after expiry',
      (tester) async {
    final message = _message()
      ..attachedInfoElem = AttachedInfoElem(
          isPrivateChat: true,
          hasReadTime: DateTime.now().millisecondsSinceEpoch,
          burnDuration: 3600);
    var taps = 0;
    await _mount(tester, message, onTap: () => taps++);
    expect(find.byType(ChatExpiringContent), findsOneWidget);
    expect(find.byType(AvatarView), findsOneWidget);
    final summary = find.text(message.textElem!.content!);
    expect(summary, findsOneWidget);
    message.attachedInfoElem!.hasReadTime =
        DateTime(2020).millisecondsSinceEpoch;
    await tester.tap(summary);
    await tester.pump(const Duration(seconds: 1));
    expect(taps, 0);
    expect(find.text('sdkExpired'.tr), findsOneWidget);
    expect(summary, findsNothing);
    expect(find.byType(AvatarView), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('voice keyword match uses its sender without audio requests',
      (tester) async {
    final message = _message()
      ..contentType = MessageType.voice
      ..soundElem = SoundElem(
          duration: 7,
          soundPath: '/private/should-not-read.m4a',
          sourceUrl: 'https://example.invalid/should-not-fetch.m4a');
    var requests = 0;
    await HttpOverrides.runZoned(() async {
      await _mount(tester, message);
      expect(find.text(message.senderNickname!.trim()), findsOneWidget);
      expect(find.byType(AvatarView), findsOneWidget);
      expect(find.textContaining(StrRes.voice), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    }, createHttpClient: (_) {
      requests++;
      throw StateError('Keyword summaries must not fetch voice attachments');
    });
    expect(requests, 0);
  });
}
