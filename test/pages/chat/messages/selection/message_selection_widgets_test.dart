import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_action_bar.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_controller.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_row.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_toolbar.dart';
import 'package:openim_common/openim_common.dart';

import 'support/selection_test_messages.dart';

const _previewKey = ValueKey('selection-preview');

Finder _action(String action) =>
    find.byKey(ValueKey('message-selection-$action'));
Finder _row(String id) => find.byKey(ValueKey('message-selection-row-$id'));
Finder _check(String id) => find.byKey(ValueKey('message-selection-check-$id'));
Finder _checkedSemantics(String id) => find.ancestor(
      of: _row(id),
      matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.checked != null),
    );

class _WidgetsFixture {
  _WidgetsFixture({List<Message>? messages})
      : messages =
            messages ?? [selectionMessage('one'), selectionMessage('two')] {
    controller = MessageSelectionController(
      messages: () => this.messages,
      isClosed: () => false,
      onStart: () {},
      deleteMessages: (messages) async {
        deleted.add(List.of(messages));
        return true;
      },
      forwardMessages: (messages, {required merged}) {
        forwarded.add(merged);
        return forwardResponse?.future ?? Future.value(false);
      },
    );
  }

  final List<Message> messages;
  late final MessageSelectionController controller;
  final forwarded = <bool>[];
  final deleted = <List<Message>>[];
  Completer<bool>? forwardResponse;

  Future<void> mount(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
    double width = 375,
    Widget? firstChild,
    bool realBubbles = false,
  }) async {
    tester.view.physicalSize = Size(width, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousDark = Styles.isDark;
    Styles.isDark = brightness == Brightness.dark;
    addTearDown(() => Styles.isDark = previousDark);
    final font = const bool.fromEnvironment('MESSAGE_SELECTION_PREVIEW')
        ? 'SelectionPreviewFont'
        : null;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(brightness: brightness, fontFamily: font),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 812),
            padding: const EdgeInsets.only(top: 24, bottom: 24),
            textScaler: TextScaler.linear(textScale),
          ),
          child: RepaintBoundary(
            key: _previewKey,
            child: Scaffold(
              backgroundColor:
                  AppTokens.background(dark: brightness == Brightness.dark),
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(TitleBar.chatToolbarHeight),
                child: MessageSelectionToolbar(controller: controller),
              ),
              body: ListView(
                children: [
                  for (var i = 0; i < messages.length; i++)
                    MessageSelectionRow(
                      key: ValueKey('fixture-row-${messages[i].clientMsgID}'),
                      controller: controller,
                      message: messages[i],
                      child: i == 0 && firstChild != null
                          ? firstChild
                          : realBubbles
                              ? ChatItemView(
                                  message: messages[i],
                                  leftNickname: '聊天好友',
                                  rightNickname: '我',
                                  leftFaceUrl: '',
                                  rightFaceUrl: '',
                                  textScaleFactor: textScale,
                                  onTapUserProfile: (_) {},
                                )
                              : SizedBox(
                                  height: 80,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child:
                                        Text('消息 ${messages[i].clientMsgID}'),
                                  ),
                                ),
                    ),
                ],
              ),
              bottomNavigationBar:
                  MessageSelectionActionBar(controller: controller),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  }
}

class _StatefulBubble extends StatefulWidget {
  const _StatefulBubble({super.key});

  @override
  State<_StatefulBubble> createState() => _StatefulBubbleState();
}

class _StatefulBubbleState extends State<_StatefulBubble> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 80,
        child: TextButton(
          key: const ValueKey('stateful-bubble-button'),
          onPressed: () => setState(() => taps++),
          child: Text('气泡状态 $taps'),
        ),
      );
}

Future<void> _loadPreviewFonts() async {
  if (!const bool.fromEnvironment('MESSAGE_SELECTION_PREVIEW')) return;
  const textFont = String.fromEnvironment('MESSAGE_SELECTION_PREVIEW_FONT',
      defaultValue: 'C:/Windows/Fonts/msyh.ttc');
  const iconsFont = String.fromEnvironment('MESSAGE_SELECTION_PREVIEW_ICONS',
      defaultValue:
          'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  for (final font in {
    'SelectionPreviewFont': textFont,
    'MaterialIcons': iconsFont,
  }.entries) {
    final loader = FontLoader(font.key)
      ..addFont(File(font.value)
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
  }
}

Future<void> _capture(WidgetTester tester, Brightness brightness) async {
  if (!const bool.fromEnvironment('MESSAGE_SELECTION_PREVIEW')) return;
  await tester.runAsync(() async {
    final render =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_previewKey));
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('.dart_tool/message-selection-${brightness.name}.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadPreviewFonts);
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: '我');
  });
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
          '${brightness.name} selection at text scale $textScale has three actions and checkbox semantics',
          (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final fixture = _WidgetsFixture();
          addTearDown(() => fixture.dispose(tester));
          fixture.controller.enter(fixture.messages.first);
          await fixture.mount(tester,
              brightness: brightness, textScale: textScale, width: 320);

          for (final id in ['forward', 'merge', 'delete']) {
            final action = _action(id);
            expect(action, findsOneWidget);
            expect(tester.widget<TextButton>(action).onPressed, isNotNull);
            expect(tester.getRect(action).height, greaterThanOrEqualTo(48));
            expect(tester.getRect(action).left, greaterThanOrEqualTo(0));
            expect(tester.getRect(action).right, lessThanOrEqualTo(320));
            final data = tester.getSemantics(action).getSemanticsData();
            expect(data.flagsCollection.isButton, isTrue);
            expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
            expect(data.label, isNotEmpty);
            expect(data.hasAction(SemanticsAction.tap), isTrue);
          }
          expect(find.text('逐条转发'), findsOneWidget);
          expect(find.text('合并转发'), findsOneWidget);
          expect(find.text('删除'), findsOneWidget);
          expect(find.text('已选择 1 条'), findsOneWidget);
          expect(_action('all'), findsNothing);
          expect(find.text('全选'), findsNothing);
          expect(find.text('取消全选'), findsNothing);
          final selected =
              tester.getSemantics(_checkedSemantics('one')).getSemanticsData();
          expect(selected.flagsCollection.isChecked, ui.CheckedState.isTrue);
          expect(selected.label, contains('选择消息'));
          expect(selected.label, contains('消息发送人'));
          expect(selected.label, contains('消息 one'));
          expect(selected.hasAction(SemanticsAction.tap), isTrue);
          expect(
              tester
                  .getSemantics(_checkedSemantics('two'))
                  .getSemanticsData()
                  .flagsCollection
                  .isChecked,
              ui.CheckedState.isFalse);
          await tester.tap(_row('two'));
          await tester.pump();
          expect(fixture.controller.count, 2);
          await tester.tap(_row('one'));
          await tester.tap(_row('two'));
          await tester.pump();
          expect(fixture.controller.count, 0);
          for (final id in ['forward', 'merge', 'delete']) {
            expect(tester.widget<TextButton>(_action(id)).onPressed, isNull);
          }
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }

    testWidgets('${brightness.name} real bubbles fit 320px during selection',
        (tester) async {
      final messages = [selectionMessage('one'), selectionMessage('two')];
      messages.first.sendID = 'me';
      messages.first.textElem!.content =
          '这是一条用于检验较窄屏幕的长消息，进入多选后，原来的聊天气泡仍应完整显示。';
      messages.last.textElem!.content = '聊天内容会保留，点击消息可切换勾选状态。';
      final fixture = _WidgetsFixture(messages: messages);
      addTearDown(() => fixture.dispose(tester));
      fixture.controller.enter(messages.first);
      await fixture.mount(tester,
          brightness: brightness, textScale: 2, width: 320, realBubbles: true);
      expect(find.byType(ChatItemView), findsNWidgets(2));
      for (final bubble in find.byType(ChatItemView).evaluate()) {
        final rect = tester.getRect(find.byWidget(bubble.widget));
        expect(rect.left, greaterThanOrEqualTo(48));
        expect(rect.right, lessThanOrEqualTo(320));
      }
      expect(_check('one'), findsOneWidget);
      expect(_check('two'), findsOneWidget);
      expect(_action('all'), findsNothing);
      expect(tester.takeException(), isNull);

      // Capture the production toolbar, action bar and original bubbles at the
      // normal font scale as a readable review artifact, separate from layout tests.
      await fixture.mount(tester, brightness: brightness, realBubbles: true);
      await _capture(tester, brightness);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('forward and merge delegate the matching operation',
      (tester) async {
    final fixture = _WidgetsFixture();
    addTearDown(() => fixture.dispose(tester));
    fixture.controller.enter(fixture.messages.first);
    await fixture.mount(tester);
    await tester.tap(_action('forward'));
    await tester.pumpAndSettle();
    await tester.tap(_action('merge'));
    await tester.pumpAndSettle();
    expect(fixture.forwarded, [false, true]);
    expect(fixture.controller.active, isTrue);
    expect(fixture.controller.count, 1);
  });

  testWidgets('busy actions disable edits but cancellation remains available',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final fixture = _WidgetsFixture();
      addTearDown(() => fixture.dispose(tester));
      fixture.forwardResponse = Completer<bool>();
      fixture.controller.enter(fixture.messages.first);
      await fixture.mount(tester);
      await tester.tap(_action('forward'));
      await tester.pump();
      expect(fixture.controller.busy, isTrue);
      for (final id in ['forward', 'merge', 'delete']) {
        expect(tester.widget<TextButton>(_action(id)).onPressed, isNull);
      }
      expect(_action('all'), findsNothing);
      expect(
          tester
              .getSemantics(_checkedSemantics('one'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse);
      expect(tester.widget<TextButton>(_action('cancel')).onPressed, isNotNull);
      await tester.tap(_action('cancel'));
      await tester.pump();
      expect(fixture.controller.active, isFalse);
      expect(_check('one'), findsOneWidget);
      expect(_check('one').hitTestable(), findsNothing);
      expect(_checkedSemantics('one'), findsNothing);
      fixture.forwardResponse!.complete(true);
      await tester.pumpAndSettle();
      expect(fixture.forwarded, [false]);
      expect(fixture.controller.busy, isFalse);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'delete asks for confirmation and cancellation preserves selection',
      (tester) async {
    final fixture = _WidgetsFixture();
    addTearDown(() => fixture.dispose(tester));
    fixture.controller.enter(fixture.messages.first);
    await fixture.mount(tester);
    await tester.tap(_action('delete'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('message-selection-delete-sheet'));
    expect(sheet, findsOneWidget);
    expect(find.text('确定删除已选的 1 条消息？'), findsOneWidget);
    await tester.tap(find.descendant(of: sheet, matching: find.text('取消')));
    await tester.pumpAndSettle();
    expect(fixture.deleted, isEmpty);
    expect(fixture.controller.count, 1);
    await tester.tap(_action('delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(CupertinoActionSheet), matching: find.text('删除')));
    await tester.pumpAndSettle();
    expect(fixture.deleted.single, [fixture.messages.first]);
    expect(fixture.controller.active, isFalse);
  });

  testWidgets('enter, toggle and cancel preserve the original bubble State',
      (tester) async {
    final fixture = _WidgetsFixture();
    addTearDown(() => fixture.dispose(tester));
    final bubbleKey = GlobalKey<_StatefulBubbleState>();
    await fixture.mount(tester, firstChild: _StatefulBubble(key: bubbleKey));
    final originalState = bubbleKey.currentState!;
    await tester.tap(find.byKey(const ValueKey('stateful-bubble-button')));
    await tester.pump();
    expect(originalState.taps, 1);
    fixture.controller.enter(fixture.messages.first);
    await tester.pump();
    expect(bubbleKey.currentState, same(originalState));
    await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('stateful-bubble-button'))));
    await tester.pump();
    expect(originalState.taps, 1,
        reason: 'selection absorbs bubble interactions');
    expect(fixture.controller.count, 0);
    fixture.controller.cancel();
    await tester.pump();
    expect(bubbleKey.currentState, same(originalState));
    expect(_check('one'), findsOneWidget);
    expect(_check('one').hitTestable(), findsNothing);
    expect(_checkedSemantics('one'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('stateful-bubble-button')));
    await tester.pump();
    expect(originalState.taps, 2);
    expect(tester.takeException(), isNull);
  });
}
