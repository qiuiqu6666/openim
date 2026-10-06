import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_controller.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_layout.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_row.dart';
import 'package:openim_common/openim_common.dart';

import 'support/selection_test_messages.dart';

MessageSelectionController _controller(List<Message> messages) =>
    MessageSelectionController(
      messages: () => messages,
      isClosed: () => false,
      onStart: () {},
      deleteMessages: (_) async => true,
      forwardMessages: (_, {required merged}) async => false,
    );

Future<void> _mount(WidgetTester tester, Widget content,
    {Brightness brightness = Brightness.light, double textScale = 1}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previousDark = Styles.isDark;
  Styles.isDark = brightness == Brightness.dark;
  addTearDown(() => Styles.isDark = previousDark);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(375, 812))
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: SingleChildScrollView(child: content)),
      ),
    ),
  ));
  // A first-frame assertion catches delayed measurement and alignment jumps.
}

Widget _decoratedBubble(String id, double height,
        {bool nickname = true,
        bool outgoing = false,
        double trailingGap = 48}) =>
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24, child: Text('11:30 时间条')),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!outgoing) const SizedBox(width: 44, height: 44),
            Expanded(
              child: Column(
                crossAxisAlignment: outgoing
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (nickname)
                    const SizedBox(height: 28, child: Text('群成员昵称')),
                  ChatMessageContentAnchor(
                    key: ValueKey('alignment-anchor-$id'),
                    messageID: id,
                    child: SizedBox(
                      key: ValueKey('alignment-content-$id'),
                      height: height,
                      width: 200,
                      child: const ColoredBox(color: Color(0xFF278CEC)),
                    ),
                  ),
                ],
              ),
            ),
            if (outgoing) const SizedBox(width: 44, height: 44),
          ],
        ),
        SizedBox(height: trailingGap),
      ],
    );

void _expectAligned(WidgetTester tester, String id, {Finder? actualContent}) {
  final check =
      tester.getRect(find.byKey(ValueKey('message-selection-check-$id')));
  final bubble = tester
      .getRect(actualContent ?? find.byKey(ValueKey('alignment-content-$id')));
  expect(check.center.dy, closeTo(bubble.center.dy, .01),
      reason: '$id must align to the content, excluding timeline and nickname');
  expect(check.height, 22);
}

class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe({required this.onPaint, required super.child});
  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintProbe(onPaint);
}

class _RenderPaintProbe extends RenderProxyBox {
  _RenderPaintProbe(this.onPaint);
  final VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

void main() {
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: '我');
  });
  tearDown(Get.reset);

  testWidgets(
      'retained indicator does not paint, hit test or expose semantics when inactive',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final selecting = ValueNotifier(false);
    addTearDown(selecting.dispose);
    var paints = 0;
    try {
      await _mount(
          tester,
          ValueListenableBuilder<bool>(
            valueListenable: selecting,
            builder: (_, value, __) => MessageSelectionLayout(
              messageID: 'paint-probe',
              selecting: value,
              indicator: _PaintProbe(
                onPaint: () => paints++,
                child: Semantics(
                  label: 'retained-selection-indicator',
                  child: const SizedBox(
                    key: ValueKey('paint-probe-indicator'),
                    width: 22,
                    height: 22,
                    child: ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
              child: const ChatMessageContentAnchor(
                messageID: 'paint-probe',
                child: SizedBox(height: 64),
              ),
            ),
          ));
      final indicator = find.byKey(const ValueKey('paint-probe-indicator'));
      final retainedElement = tester.element(indicator);
      expect(indicator, findsOneWidget);
      expect(paints, 0);
      expect(indicator.hitTestable(), findsNothing);
      expect(
          find.semantics.byLabel('retained-selection-indicator'), findsNothing);

      selecting.value = true;
      await tester.pump();
      expect(paints, greaterThan(0));
      expect(indicator.hitTestable(), findsOneWidget);
      expect(find.semantics.byLabel('retained-selection-indicator'),
          findsOneWidget);
      final activePaints = paints;

      selecting.value = false;
      await tester.pump();
      expect(tester.element(indicator), same(retainedElement));
      expect(paints, activePaints);
      expect(indicator.hitTestable(), findsNothing);
      expect(
          find.semantics.byLabel('retained-selection-indicator'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} first frame aligns short, tall and media content',
        (tester) async {
      final messages = [
        selectionMessage('short'),
        selectionMessage('tall'),
        selectionMessage('media'),
      ];
      final controller = _controller(messages);
      addTearDown(controller.dispose);
      controller.enter(messages.first);
      await _mount(
          tester,
          Column(children: [
            MessageSelectionRow(
                controller: controller,
                message: messages[0],
                child: _decoratedBubble('short', 24, trailingGap: 90)),
            MessageSelectionRow(
                controller: controller,
                message: messages[1],
                child: _decoratedBubble('tall', 96,
                    nickname: false, outgoing: true)),
            MessageSelectionRow(
                controller: controller,
                message: messages[2],
                child: _decoratedBubble('media', 168, trailingGap: 8)),
          ]),
          brightness: brightness);
      for (final id in ['short', 'tall', 'media']) {
        _expectAligned(tester, id);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${brightness.name} dynamic content height updates in the same layout',
        (tester) async {
      final message = selectionMessage('resizable');
      final controller = _controller([message]);
      addTearDown(controller.dispose);
      final height = ValueNotifier(24.0);
      addTearDown(height.dispose);
      controller.enter(message);
      await _mount(
          tester,
          MessageSelectionRow(
            controller: controller,
            message: message,
            child: ValueListenableBuilder<double>(
              valueListenable: height,
              builder: (_, value, __) => _decoratedBubble('resizable', value),
            ),
          ),
          brightness: brightness);
      _expectAligned(tester, 'resizable');
      final before = tester
          .getRect(
              find.byKey(const ValueKey('message-selection-check-resizable')))
          .center
          .dy;
      height.value = 184;
      await tester.pump();
      _expectAligned(tester, 'resizable');
      expect(
          tester
              .getRect(find
                  .byKey(const ValueKey('message-selection-check-resizable')))
              .center
              .dy,
          closeTo(before + 80, .01));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${brightness.name} original chat bubbles exclude timeline and nickname at large text',
        (tester) async {
      final messages = [selectionMessage('received'), selectionMessage('sent')];
      messages.last.sendID = 'me';
      messages.first.textElem!.content = '这条消息有多行内容，检验群聊昵称和时间条不影响选择圆点的中心位置。';
      final controller = _controller(messages);
      addTearDown(controller.dispose);
      controller.enter(messages.first);
      await _mount(
          tester,
          Column(children: [
            for (final message in messages)
              MessageSelectionRow(
                controller: controller,
                message: message,
                child: ChatItemView(
                  message: message,
                  timelineStr: '周五 11:30',
                  leftNickname: '群聊成员昵称',
                  leftFaceUrl: '',
                  rightFaceUrl: '',
                  rightNickname: '我',
                  showLeftNickname: true,
                  textScaleFactor: 2,
                  onTapUserProfile: (_) {},
                ),
              ),
          ]),
          brightness: brightness,
          textScale: 2);
      for (final message in messages) {
        final content = find.byWidgetPredicate((widget) =>
            widget is ChatMessageContentAnchor &&
            widget.messageID == message.clientMsgID);
        expect(content, findsOneWidget);
        _expectAligned(tester, message.clientMsgID!, actualContent: content);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
