import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_source.dart';

import 'support/chat_history_sender_presence_fixture.dart';

// Opt-in actual-widget exports; sample members/presence are test data only.
// --dart-define=CHAT_SENDER_PRESENCE_PREVIEW_DIR=E:/openim/.temp/chat-sender-presence-preview
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadSenderPresencePreviewFonts);
  for (final brightness in Brightness.values) {
    for (final (width, scale, suffix) in const [
      (390.0, 1.0, ''),
      (320.0, 2.0, '-large'),
    ]) {
      testWidgets('export ${brightness.name} sender presence$suffix',
          skip: senderPresencePreviewDirectory.isEmpty, (tester) async {
        final members = senderPresenceSamples().toList();
        if (suffix.isNotEmpty) {
          members[0] = const ChatHistorySender(
              userID: '1001', displayName: senderLongName);
        }
        final fixture = SenderPresenceFixture(
            source: SenderPresenceSource(members: members));
        await fixture.open(tester,
            brightness: brightness,
            width: width,
            textScale: scale,
            fontFamily: 'ChatSenderPreviewCjk');
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
          final output = Directory(senderPresencePreviewDirectory);
          await output.create(recursive: true);
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/chat-sender-${brightness.name}$suffix.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
          await File('${output.path}/preview-notes.txt').writeAsString(
            '发送人选择页真实 Flutter Widget；示例成员与在线状态仅为测试夹具。\n'
            '标准 390×844；large 320×844、200% 字号；2 倍输出；微软雅黑。\n'
            '包含在线、3 小时前离线、隐私隐藏、未知四种状态，无服务端请求。\n',
          );
        });
      });
    }
  }
}
