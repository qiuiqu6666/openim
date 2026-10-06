import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_history_voice_fixture.dart';

// flutter test test/pages/chat/history_search/voice/chat_history_voice_preview_test.dart
//   --dart-define=CHAT_VOICE_PREVIEW_DIR=E:/openim/.temp/chat-voice-style-preview
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadVoicePreviewFonts);
  for (final brightness in Brightness.values) {
    for (final (width, scale, suffix) in const [
      (390.0, 1.0, ''),
      (320.0, 2.0, '-large'),
    ]) {
      testWidgets('export actual ${brightness.name} voice results$suffix',
          skip: voicePreviewDirectory.isEmpty, (tester) async {
        final boundary = GlobalKey();
        final source = VoiceTestSource()..messages = voiceSamples();
        await pumpVoicePage(tester, source,
            brightness: brightness,
            width: width,
            textScale: scale,
            boundaryKey: boundary,
            fontFamily: 'ChatVoicePreviewCjk');
        expect(tester.takeException(), isNull);
        final render = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final output = Directory(voicePreviewDirectory);
          await output.create(recursive: true);
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/chat-voice-${brightness.name}$suffix.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
          await File('${output.path}/preview-notes.txt').writeAsString(
            '语音搜索真实 Flutter Widget 渲染，测试消息 7/4/2 秒及长发送人。\n'
            '逻辑尺寸 390×844；图片尺寸 780×1688；微软雅黑；使用实际页面主题 token。\n'
            '*-large 为 320×844，200% 字号，输出 640×1688。\n'
            '仅测试夹具，不代表真实聊天；不下载或播放音频，不访问服务端。\n',
          );
        });
      });
    }
  }
}
