import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/voice/chat_voice_panel_layout.dart';
import 'package:openim_common/src/widgets/chat/voice/chat_voice_panel_view.dart';
import 'package:openim_common/src/widgets/chat/voice/chat_voice_waveform.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'voice states keep the panel fixed and fit small screens / $dark',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final width in [320.0, 375.0]) {
        tester.view.physicalSize = Size(width, 812);
        for (final scale in [1.0, 1.5, 2.0]) {
          for (final inset in [0.0, 34.0]) {
            tester.view.padding = FakeViewPadding(bottom: inset);
            tester.view.viewPadding = FakeViewPadding(bottom: inset);
            final height = 248 + inset;
            final micKey = GlobalKey();
            Rect? normalMic;
            for (final state in ['idle', 'busy', 'error']) {
              await _pumpVisual(
                tester,
                dark: dark,
                scale: scale,
                settle: state != 'busy',
                child: Column(children: [
                  const Spacer(),
                  ChatVoiceIdlePanel(
                    height: height,
                    micKey: micKey,
                    busy: state == 'busy',
                    errorText:
                        state == 'error' ? '麦克风暂时不可用，请检查权限后再次尝试录音' : null,
                  ),
                ]),
              );
              final panel = tester.getRect(_key('chat-voice-idle-panel'));
              final mic = tester.getRect(find.byKey(micKey));
              expect(panel.size, Size(width, height));
              expect(panel.bottom, 812);
              expect(mic.size, const Size(80, 80));
              expect(mic.center.dx, panel.center.dx);
              normalMic ??= mic;
              expect(mic, normalMic,
                  reason:
                      'Processing or an error must not move the microphone');
              _expectWithin(mic, panel);
              final title = tester.getRect(_key('chat-voice-idle-title'));
              final hint = tester.getRect(_key('chat-voice-idle-hint'));
              _expectWithin(title, panel);
              _expectWithin(hint, panel);
              _expectNoOverlap(title, hint,
                  reason:
                      'The title and guidance must not overlap at scale=$scale');
              _expectNoOverlap(title, mic,
                  reason:
                      'The title must not cover the microphone at scale=$scale');
              _expectNoOverlap(hint, mic,
                  reason:
                      'Guidance or errors must not cover the microphone at scale=$scale');
              expect(find.text(state == 'busy' ? '正在处理…' : '按住说话'),
                  findsOneWidget);
              if (state == 'error') {
                expect(find.text('麦克风暂时不可用，请检查权限后再次尝试录音'), findsOneWidget);
              } else {
                expect(
                    find.text(state == 'busy'
                        ? (scale > 1.5 ? '请稍候' : '正在处理录音，请稍候')
                        : (scale > 1.5 ? '松开发送，滑动切换' : '松开发送，向两侧滑动切换操作')),
                    findsOneWidget);
              }
            }

            Rect? normalRecordingPanel;
            for (final zone in ChatVoiceReleaseZone.values) {
              await _pumpVisual(tester,
                  dark: dark,
                  scale: scale,
                  child: ChatVoiceRecordingOverlay(
                    anchorGlobal: null,
                    zone: zone,
                    seconds: 37,
                    levels: const [.1, .3, .8, .5, .2],
                  ));
              final panel = tester.getRect(_key('chat-voice-panel'));
              expect(panel.size, Size(width, height));
              expect(panel.bottom, 812);
              normalRecordingPanel ??= panel;
              expect(panel, normalRecordingPanel,
                  reason: 'Release-zone changes must preserve panel geometry');
              expect(find.text('00:37'), findsOneWidget);
              final status = switch (zone) {
                ChatVoiceReleaseZone.send => '正在录音',
                ChatVoiceReleaseZone.cancel => '松开取消',
                ChatVoiceReleaseZone.convertText => '松开转文字',
              };
              expect(find.text(status), findsOneWidget);
              _expectWithin(tester.getRect(_key('chat-voice-status')), panel);
              _expectWithin(tester.getRect(_key('chat-voice-duration')), panel);
              _expectWithin(tester.getRect(_key('chat-voice-waveform')), panel);
              for (final control in ['cancel', 'send', 'convertText']) {
                _expectWithin(
                    tester.getRect(_key('chat-voice-control-$control')), panel);
                _expectWithin(
                    tester.getRect(_key('chat-voice-control-label-$control')),
                    panel);
              }
              final cancel = tester.getRect(_key('chat-voice-control-cancel'));
              final send = tester.getRect(_key('chat-voice-control-send'));
              final convert =
                  tester.getRect(_key('chat-voice-control-convertText'));
              expect(cancel.right, lessThan(send.left));
              expect(send.right, lessThan(convert.left));
              expect(send.size, const Size(80, 80));
              expect(cancel.center.dy, send.center.dy);
              expect(convert.center.dy, send.center.dy);
            }
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'preparation, duration and disabled conversion are explicit / $dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 812);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      try {
        await _pumpVisual(tester,
            dark: dark,
            scale: 2,
            settle: false,
            child: const ChatVoiceRecordingOverlay(
              anchorGlobal: null,
              zone: ChatVoiceReleaseZone.send,
              preparing: true,
            ));
        final preparingRect = tester.getRect(_key('chat-voice-panel'));
        expect(find.text('准备中…'), findsOneWidget);
        expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
        expect(find.byType(ChatVoiceWaveform), findsNothing);

        await _pumpVisual(tester,
            dark: dark,
            scale: 2,
            child: const ChatVoiceRecordingOverlay(
              anchorGlobal: null,
              zone: ChatVoiceReleaseZone.convertText,
              allowConvert: false,
              seconds: 65,
              levels: [.2, .7, .3],
            ));
        expect(tester.getRect(_key('chat-voice-panel')), preparingRect);
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(find.text('01:05'), findsOneWidget);
        expect(find.text('正在录音'), findsOneWidget);
        expect(find.text('松开转文字'), findsNothing);
        expect(find.text('转文字'), findsNothing);
        expect(_key('chat-voice-control-convertText'), findsNothing);
        expect(find.byType(ChatVoiceWaveform), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('正在录音.*65')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
        'voice mode preserves the text draft and cursor on return / $dark',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);
      final controller = TextEditingController.fromValue(const TextEditingValue(
          text: '保留草稿', selection: TextSelection.collapsed(offset: 2)));
      final focus = FocusNode();
      final micKey = GlobalKey();
      await tester.pumpWidget(GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        theme: ThemeData(
            platform: TargetPlatform.iOS,
            brightness: dark ? Brightness.dark : Brightness.light),
        home: Material(
            child: Column(children: [
          const Spacer(),
          ChatInputBox(
              controller: controller,
              focusNode: focus,
              onTapVoice: () {},
              toolbox: const SizedBox(),
              voiceRecordBar: ChatVoiceIdlePanel(height: 282, micKey: micKey)),
        ])),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(StrRes.voiceCapture));
      await tester.pumpAndSettle();
      final panel = _key('chat-voice-panel-slot');
      final placeholder = _key('chat-voice-input-placeholder');
      expect(tester.getSize(panel), const Size(375, 282));
      expect(tester.getRect(panel).bottom, 812);
      expect(tester.getSize(placeholder).height, 36);
      expect(find.byType(ChatTextField), findsNothing);
      expect(
          controller.value,
          const TextEditingValue(
              text: '保留草稿', selection: TextSelection.collapsed(offset: 2)));
      await tester.tap(placeholder);
      await tester.pump();
      expect(panel, findsNothing);
      expect(find.byType(ChatTextField), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(controller.text, '保留草稿');
      expect(controller.selection.baseOffset, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      focus.dispose();
    });
  }

  testWidgets(
      'visible waveform follows real samples and stays still for silence',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundaryKey = GlobalKey();
    Future<Uint8List> capture(List<double> levels) async {
      await _pumpVisual(tester,
          dark: false,
          scale: 1,
          child: RepaintBoundary(
            key: boundaryKey,
            child: ChatVoiceRecordingOverlay(
              anchorGlobal: null,
              zone: ChatVoiceReleaseZone.send,
              seconds: 37,
              levels: levels,
            ),
          ));
      final waveform =
          tester.widget<ChatVoiceWaveform>(find.byType(ChatVoiceWaveform));
      expect(waveform.levels, orderedEquals(levels));
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final pixels = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return bytes!.buffer.asUint8List();
      });
      return pixels!;
    }

    final silent = List<double>.filled(24, 0);
    final recorded = List<double>.generate(24, (index) => (index % 5) / 4);
    final firstSilence = await capture(silent);
    await tester.pump(const Duration(seconds: 1));
    final secondSilence = await capture(silent);
    expect(secondSilence, orderedEquals(firstSilence),
        reason: 'Silence must not create a synthetic animated waveform');
    final sound = await capture(recorded);
    expect(sound, isNot(orderedEquals(firstSilence)),
        reason: 'New native samples must change the visible waveform');
    final repeatedSound = await capture(recorded);
    expect(repeatedSound, orderedEquals(sound),
        reason: 'The same native samples must render deterministically');
    await tester.pumpWidget(const SizedBox());
  });
}

Finder _key(String value) => find.byKey(ValueKey(value));

void _expectWithin(Rect inner, Rect outer) {
  expect(inner.left, greaterThanOrEqualTo(outer.left - .01));
  expect(inner.top, greaterThanOrEqualTo(outer.top - .01));
  expect(inner.right, lessThanOrEqualTo(outer.right + .01));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + .01));
}

void _expectNoOverlap(Rect first, Rect second, {required String reason}) {
  expect(first.overlaps(second), isFalse, reason: reason);
}

Future<void> _pumpVisual(WidgetTester tester,
    {required bool dark,
    required double scale,
    required Widget child,
    bool settle = true}) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
        platform: TargetPlatform.iOS,
        brightness: dark ? Brightness.dark : Brightness.light),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Material(child: child),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 150));
  }
  expect(tester.takeException(), isNull);
}
