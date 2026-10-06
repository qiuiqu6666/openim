import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_setup/message_context_page.dart';
import 'package:openim/pages/chat/history_search/chat_history_category.dart';
import 'package:openim/pages/chat/history_search/chat_history_results_page.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim/pages/chat/history_search/navigation/chat_history_message_navigation.dart';
import 'package:openim/pages/chat/media/widgets/chat_video_thumbnail.dart';
import 'package:openim/pages/chat/stickers/sticker_video_message.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NavigationProbe extends ChatHistoryMessageNavigation {
  final calls = <({String conversationID, Message message})>[];

  @override
  Future<bool> open(BuildContext context,
      {required String conversationID,
      required Message message,
      required bool Function() isEntryCurrent}) async {
    expect(isEntryCurrent(), isTrue);
    calls.add((conversationID: conversationID, message: message));
    return true;
  }
}

class _Source implements ChatHistorySearchSource {
  List<Message> messages = [];
  final queries = <ChatHistorySearchQuery>[];
  final pages = <int>[];
  int failures = 0;
  Completer<List<Message>>? pending;

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    expect(conversationID, 'asset-chat');
    expect(count, 30);
    queries.add(query);
    pages.add(pageIndex);
    if (failures > 0) {
      --failures;
      throw StateError('Unavailable');
    }
    return pending?.future ?? messages;
  }
}

Finder _result(String id) => find.byKey(ValueKey('chat-history-result-$id'));
Finder get _scroll => find
    .descendant(
        of: find.byType(RefreshIndicator), matching: find.byType(Scrollable))
    .first;

Message _message(
  String id,
  int type,
  String path, {
  bool private = false,
  bool expired = false,
  String? fileName,
}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': type,
      'sessionType': ConversationType.single,
      'sendID': 'self',
      'recvID': 'peer',
      'senderNickname': 'Sender should not appear in a media grid',
      'sendTime': DateTime(2024, 6, 15, 12).millisecondsSinceEpoch,
      'status': MessageStatus.succeeded,
      if (type == MessageType.picture)
        'pictureElem': {
          'sourcePath': path,
          'sourcePicture': {'width': 1, 'height': 1}
        },
      if (type == MessageType.video)
        'videoElem': {'snapshotPath': path, 'videoPath': '', 'duration': 12},
      if (type == MessageType.file)
        'fileElem': {
          'filePath': path,
          'fileName': fileName ?? 'report.pdf',
          'fileSize': 4096
        },
      if (type == MessageType.voice)
        'soundElem': {'duration': 7, 'soundPath': ''},
      if (private || expired)
        'attachedInfoElem': {
          'isPrivateChat': true,
          'burnDuration': 60,
          if (expired) 'hasReadTime': DateTime(2020).millisecondsSinceEpoch,
        },
    });

Future<void> _finishIo(WidgetTester tester) async {
  // The grid resolves local files, then a gallery route resolves its originals.
  // Advance both frame/IO phases before settling indeterminate progress widgets.
  for (var phase = 0; phase < 3; phase++) {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late Directory directory;
  late String imagePath;
  late _Source source;
  late _NavigationProbe messageNavigation;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('chat-history-assets-');
    imagePath = '${directory.path}/thumbnail.png';
    await File(imagePath).writeAsBytes(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a/q8AAAAASUVORK5CYII='));
  });
  tearDownAll(() async {
    // Image decoding can briefly retain the Windows fixture handle.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    for (var attempt = 0;; attempt++) {
      try {
        await directory.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt >= 9) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });
  setUp(() async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    source = _Source();
    messageNavigation = _NavigationProbe();
  });
  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> mount(
    WidgetTester tester,
    ChatHistoryCategory category, {
    Brightness brightness = Brightness.light,
    double width = 390,
    double scale = 1,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final wasDark = Styles.isDark;
    Styles.isDark = brightness == Brightness.dark;
    addTearDown(() => Styles.isDark = wasDark);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _finishIo(tester);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        theme: ThemeData(brightness: brightness),
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ChatHistoryResultsPage(
          conversationID: 'asset-chat',
          category: category,
          source: source,
          messageNavigation: messageNavigation,
        ),
      ),
    ));
    if (settle) await _finishIo(tester);
  }

  for (final brightness in Brightness.values) {
    for (final width in [390.0, 480.0]) {
      testWidgets(
          'picture grid uses square ${width < 480 ? 3 : 4} columns ($brightness)',
          (tester) async {
        source.messages = [
          for (var i = 0; i < 8; i++)
            _message('p$i', MessageType.picture, imagePath)
        ];
        await mount(tester, ChatHistoryCategory.picture,
            brightness: brightness, width: width);
        final columns = width < 480 ? 3 : 4;
        final first = tester.getRect(_result('p0'));
        final second = tester.getRect(_result('p1'));
        final next = tester.getRect(_result('p$columns'));
        expect(first.width, closeTo(first.height, .01));
        expect(first.left, closeTo(2, .01));
        expect(second.left - first.right, closeTo(2, .01));
        expect(second.top, closeTo(first.top, .01));
        expect(next.left, closeTo(first.left, .01));
        expect(next.top - first.bottom, closeTo(2, .01));
        expect(first.width,
            closeTo((width - 4 - (columns - 1) * 2) / columns, .01));
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(ListTile), findsNothing);
        expect(find.text('Sender should not appear in a media grid'),
            findsNothing);
        expect(find.byIcon(Icons.chevron_right), findsNothing);
        expect(source.queries.single.messageTypes, [MessageType.picture]);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        'file list keeps exact long filename, search and ordinary rows ($brightness)',
        (tester) async {
      const name =
          '跨部门费用结算说明_本月核对材料_This_is_a_long_document_name_without_a_prefix.pdf';
      source.messages = [
        _message('document', MessageType.file, imagePath, fileName: name)
      ];
      await mount(tester, ChatHistoryCategory.file,
          brightness: brightness, width: 320, scale: 2);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(name), findsOneWidget);
      expect(find.text('[文件] $name'), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byType(ChatFileMessageView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'video grid has a play overlay and remains separate from pictures',
      (tester) async {
    source.messages = [_message('video', MessageType.video, imagePath)];
    await mount(tester, ChatHistoryCategory.video);
    final tile = _result('video');
    expect(
        find.descendant(
            of: tile, matching: find.byIcon(Icons.play_circle_fill)),
        findsOneWidget);
    final rect = tester.getRect(tile);
    expect(rect.width, closeTo(rect.height, .01));
    expect(source.queries.single.messageTypes, [MessageType.video]);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picture thumbnail falls back past blank snapshot URLs',
      (tester) async {
    const original = 'https://example.com/original.png';
    final picture = _message('fallback', MessageType.picture, '');
    picture.pictureElem!
      ..sourcePath = null
      ..snapshotPicture = PictureInfo(url: ' ')
      ..bigPicture = null
      ..sourcePicture = PictureInfo(url: original);
    source.messages = [picture];
    await mount(tester, ChatHistoryCategory.picture);
    final thumbnail = tester.widget<ChatVideoThumbnail>(find.descendant(
        of: _result('fallback'), matching: find.byType(ChatVideoThumbnail)));
    expect(thumbnail.path, isNull);
    expect(thumbnail.url, original);
    expect(tester.takeException(), isNull);
  });

  testWidgets('video category excludes sticker videos from its result grid',
      (tester) async {
    final sticker = _message('sticker', MessageType.video, imagePath);
    markStickerVideoMessage(sticker);
    source.messages = [
      sticker,
      _message('ordinary', MessageType.video, imagePath)
    ];
    await mount(tester, ChatHistoryCategory.video);
    expect(_result('ordinary'), findsOneWidget);
    expect(_result('sticker'), findsNothing);
    expect(find.byType(ChatVideoThumbnail), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(source.queries.single.messageTypes, [MessageType.video]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'picture opens gallery, swipes and returns without a search or scroll reset',
      (tester) async {
    source.messages = [
      for (var i = 0; i < 27; i++)
        _message('picture-$i', MessageType.picture, imagePath),
      _message('private', MessageType.picture, imagePath, private: true),
      _message('expired', MessageType.picture, imagePath, expired: true),
    ];
    await mount(tester, ChatHistoryCategory.picture);
    await tester.drag(_scroll, const Offset(0, -350));
    await _finishIo(tester);
    final before = tester.state<ScrollableState>(_scroll).position.pixels;
    expect(before, greaterThan(0));
    await tester.runAsync(() async {
      await tester.tap(_result('picture-18'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await _finishIo(tester);
    expect(find.byType(MediaBrowser), findsOneWidget);
    expect(find.byType(MessageContextPage), findsNothing);
    expect(messageNavigation.calls, isEmpty);
    final browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
    expect(browser.initialIndex, 18);
    expect(browser.sources, hasLength(27));
    expect(browser.sources.map((item) => item.tag), isNot(contains('private')));
    expect(browser.sources.map((item) => item.tag), isNot(contains('expired')));
    final pages = find.byType(ExtendedImageGesturePageView);
    final pager = tester.widget<ExtendedImageGesturePageView>(pages);
    expect(pager.controller.page, closeTo(18, .01));
    await tester.drag(pages, const Offset(-320, 0));
    await _finishIo(tester);
    expect(pager.controller.page, closeTo(19, .01));
    await tester.tap(find.descendant(
        of: find.byType(MediaBrowser), matching: find.byTooltip('返回')));
    await _finishIo(tester);
    expect(find.byType(MediaBrowser), findsNothing);
    expect(source.queries, hasLength(1));
    expect(tester.state<ScrollableState>(_scroll).position.pixels,
        closeTo(before, .01));
    expect(tester.takeException(), isNull);
  });

  for (final category in [
    ChatHistoryCategory.picture,
    ChatHistoryCategory.file,
    ChatHistoryCategory.voice,
  ]) {
    testWidgets(
        '${category.name} handles loading, retry, empty and pull-to-refresh',
        (tester) async {
      source.pending = Completer<List<Message>>();
      await mount(tester, category, settle: false);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      source.pending!.completeError(StateError('offline'));
      source.pending = null;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-history-retry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-history-retry')));
      await tester.pumpAndSettle();
      expect(find.text('chatSearchEmpty'.tr), findsOneWidget);
      expect(source.pages, [1, 1]);
      source.messages = [
        _message(
            'refreshed',
            switch (category) {
              ChatHistoryCategory.picture => MessageType.picture,
              ChatHistoryCategory.voice => MessageType.voice,
              _ => MessageType.file,
            },
            imagePath)
      ];
      await tester.drag(_scroll, const Offset(0, 400));
      await _finishIo(tester);
      expect(source.pages, [1, 1, 1]);
      expect(_result('refreshed'), findsOneWidget);
      expect(find.text('chatSearchEmpty'.tr), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final category in [
    ChatHistoryCategory.picture,
    ChatHistoryCategory.video
  ]) {
    testWidgets(
        'expired ${category.name} never builds a thumbnail or opens media',
        (tester) async {
      final type = category == ChatHistoryCategory.picture
          ? MessageType.picture
          : MessageType.video;
      source.messages = [_message('expired', type, imagePath, expired: true)];
      await mount(tester, category);
      expect(find.text('sdkExpired'.tr), findsOneWidget);
      expect(find.byType(ChatVideoThumbnail), findsNothing);
      expect(find.byType(Image), findsNothing);
      await tester.tap(_result('expired'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowser), findsNothing);
      expect(find.byType(MessageContextPage), findsNothing);
      expect(messageNavigation.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('private picture requests the original chat without a gallery',
      (tester) async {
    final private =
        _message('private', MessageType.picture, imagePath, private: true);
    source.messages = [private];
    await mount(tester, ChatHistoryCategory.picture);
    await tester.tap(_result('private'));
    await _finishIo(tester);
    expect(find.byType(MediaBrowser), findsNothing);
    expect(messageNavigation.calls, hasLength(1));
    final call = messageNavigation.calls.single;
    expect(call.conversationID, 'asset-chat');
    expect(call.message.clientMsgID, private.clientMsgID);
    expect(call.message, same(private));
    expect(call.message.attachedInfoElem?.isPrivateChat, isTrue);
    expect(find.byType(MessageContextPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
