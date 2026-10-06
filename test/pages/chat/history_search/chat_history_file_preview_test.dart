import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history_search/chat_history_category.dart';
import 'package:openim/pages/chat/history_search/chat_history_results_page.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Opt-in screenshots of the actual page; all sample attachments stay in tests.
// flutter test test/pages/chat/history_search/chat_history_file_preview_test.dart
//   --dart-define=CHAT_FILE_PREVIEW_DIR=E:/openim/.temp/chat-file-colors-preview
const _directory = String.fromEnvironment('CHAT_FILE_PREVIEW_DIR');

class _PreviewSource implements ChatHistorySearchSource {
  _PreviewSource(this.localPath);

  final String localPath;

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    const names = [
      '项目说明.pdf',
      '项目会议记录.docx',
      '项目资料：交付清单与验收说明（最终确认版）.xlsx',
      '项目设计素材.zip',
      '项目使用指南.pdf',
    ];
    final today = DateTime.now();
    return [
      for (var i = 0; i < names.length; i++)
        if (names[i].contains(query.keyword))
          Message.fromJson({
            'clientMsgID': 'preview-file-$i',
            'contentType': MessageType.file,
            'sessionType': ConversationType.single,
            'sendID': 'preview-self',
            'recvID': 'preview-peer',
            'senderNickname': '预览会话',
            'sendTime': DateTime(
                    today.year, today.month, today.day - i, 14 - i, 8 + i * 7)
                .millisecondsSinceEpoch,
            'status': MessageStatus.succeeded,
            'fileElem': {
              'filePath': i.isEven ? localPath : '',
              'fileName': names[i],
              'fileSize': 4096,
            },
          }),
    ];
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  await tester.runAsync(() async {
    for (final image in images) {
      await precacheImage(image.image, key.currentContext!);
    }
  });
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final render =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Directory? fixtures;
  late String localPath;

  setUpAll(() async {
    if (_directory.isEmpty) return;
    for (final font in {
      'ChatFilePreviewCjk': 'C:/Windows/Fonts/msyh.ttc',
      'MaterialIcons':
          'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)
            ..addFont(File(font.value)
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes))))
          .load();
    }
    fixtures = await Directory.systemTemp.createTemp('chat-file-preview-');
    localPath = '${fixtures!.path}/preview.pdf';
    await File(localPath).writeAsString('Test-only file-state fixture.');
    await Directory(_directory).create(recursive: true);
  });

  tearDownAll(() async {
    await fixtures?.delete(recursive: true);
  });

  for (final brightness in Brightness.values) {
    testWidgets('export actual file results ${brightness.name} preview',
        skip: _directory.isEmpty, (tester) async {
      Get.testMode = true;
      OpenIM.iMManager.userID = 'preview-self';
      OpenIM.iMManager.userInfo = UserInfo(userID: 'preview-self');
      SharedPreferences.setMockInitialValues({});
      await SpUtil().init();
      final previousDark = Styles.isDark;
      final dark = brightness == Brightness.dark;
      // Match the host app's base palette; the actual page supplies its own
      // neutral file-search surfaces and content colors from shared tokens.
      final surface = dark ? const Color(0xFF202A36) : Colors.white;
      final foreground =
          dark ? const Color(0xFFE8EDF5) : const Color(0xFF0C1C33);
      Styles.isDark = dark;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      final boundary = GlobalKey();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        Styles.isDark = previousDark;
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        Get.reset();
      });

      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: brightness,
            fontFamily: 'ChatFilePreviewCjk',
            colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xFF0089FF),
                    brightness: brightness,
                    surface: surface)
                .copyWith(onSurface: foreground),
            scaffoldBackgroundColor:
                dark ? const Color(0xFF141D27) : const Color(0xFFF8F9FA),
            canvasColor: surface,
            appBarTheme: const AppBarTheme(scrolledUnderElevation: 0),
          ),
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: RepaintBoundary(
            key: boundary,
            child: ChatHistoryResultsPage(
              conversationID: 'preview-chat',
              category: ChatHistoryCategory.file,
              source: _PreviewSource(localPath),
            ),
          ),
        ),
      ));
      for (var phase = 0; phase < 3; phase++) {
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
      }
      await tester.pumpAndSettle();
      await _capture(tester, boundary, 'chat-files-${brightness.name}');

      // Also render entered text and the clear action using the real SearchBox.
      await tester.enterText(find.byType(TextField), '项目');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
      await _capture(tester, boundary, 'chat-files-${brightness.name}-search');
      await tester.runAsync(() async {
        await File('$_directory/preview-notes.txt').writeAsString(
          '聊天文件结果页真实 Flutter Widget 渲染，测试源提供示例文件，不代表真实会话。\n'
          '逻辑尺寸 390×844；输出尺寸 780×1688；微软雅黑；亮/暗主题同布局。\n'
          '已下载及未下载状态由测试本地文件存在性驱动；未访问服务器、未打开文件。\n'
          '*-search 为实际输入并提交“项目”后的页面，展示输入文字及清空图标。\n',
        );
      });
    });
  }
}
