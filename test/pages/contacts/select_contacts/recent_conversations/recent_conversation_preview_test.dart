import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recent_conversation_fixture.dart';

// Opt-in exports of the actual production page using test-only conversations.
// --dart-define=RECENT_CONVERSATION_PREVIEW_DIR=E:/openim/.temp/recent-conversation-preview
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRecentConversationPreviewFonts);
  for (final brightness in Brightness.values) {
    for (final (width, scale, suffix) in const [
      (390.0, 1.0, ''),
      (320.0, 2.0, '-large'),
    ]) {
      testWidgets('export ${brightness.name} recent conversations$suffix',
          skip: recentConversationPreviewDirectory.isEmpty, (tester) async {
        final data = recentConversationSamples();
        if (suffix.isNotEmpty) {
          data[0].showName = recentLongName;
          data[0].latestMsg = recentMessage(text: recentLongPreview);
        }
        final fixture = RecentConversationFixture(data: data);
        await fixture.open(tester,
            brightness: brightness,
            width: width,
            textScale: scale,
            fontFamily: 'RecentConversationPreviewCjk');
        await tester.tap(recentConversationRow('single'));
        await tester.pumpAndSettle();
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        await tester.runAsync(() async {
          for (final image in images) {
            await precacheImage(image.image, fixture.boundary.currentContext!);
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final render = fixture.boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final output = Directory(recentConversationPreviewDirectory);
          await output.create(recursive: true);
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
                  '${output.path}/recent-conversations-${brightness.name}$suffix.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
          await File('${output.path}/preview-notes.txt').writeAsString(
            '真实 SelectContactsPage 最近会话页面及选择 Controller，测试消息与联系人。\n'
            '标准390×844；large320×844、200%字号；2倍输出；微软雅黑。\n'
            '已实际点击选中首项；含普通/群聊文本、语音、文件、私密及无消息会话。\n'
            '首项显示未读数量，群聊同时显示未读数量与草稿前缀。\n'
            '仅测试使用数据，未访问 SDK 服务器或修改真实会话。\n',
          );
        });
      });
    }
  }
}
