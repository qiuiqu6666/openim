import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_controller.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_drag_region.dart';
import 'package:openim/pages/chat/messages/selection/message_selection_row.dart';
import 'package:openim_common/openim_common.dart';

import 'support/selection_test_messages.dart';

const _screen = Size(375, 720);

class _DragFixture {
  _DragFixture({int count = 12, this.reverse = false})
      : messages =
            List.generate(count, (index) => selectionMessage('row-$index')) {
    selection = MessageSelectionController(
      messages: () => messages,
      isClosed: () => false,
      onStart: () {},
      deleteMessages: (_) async => true,
      forwardMessages: (_, {required merged}) async => false,
    );
  }

  final List<Message> messages;
  final bool reverse;
  final scroll = ScrollController();
  late final MessageSelectionController selection;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        theme: ThemeData.light(),
        home: Scaffold(
          body: MessageSelectionDragRegion(
            controller: selection,
            scrollController: scroll,
            child: ListView.builder(
              key: const ValueKey('selection-drag-list'),
              controller: scroll,
              reverse: reverse,
              padding: EdgeInsets.zero,
              itemCount: messages.length,
              itemBuilder: (_, index) => MessageSelectionRow(
                key: ValueKey('drag-row-${messages[index].clientMsgID}'),
                controller: selection,
                message: messages[index],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: ChatMessageContentAnchor(
                    messageID: messages[index].clientMsgID!,
                    child: SizedBox(
                      key: ValueKey('drag-content-$index'),
                      height: 64,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('消息 $index'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Offset point(WidgetTester tester, int index) =>
      tester.getCenter(find.byKey(ValueKey('drag-content-$index')));

  Future<TestGesture> hold(WidgetTester tester, int index) async {
    final gesture = await tester.startGesture(point(tester, index));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    return gesture;
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    selection.dispose();
    scroll.dispose();
  }
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  testWidgets(
      'long press selects a contiguous range and backtracking restores baseline',
      (tester) async {
    final fixture = _DragFixture();
    addTearDown(() => fixture.dispose(tester));
    fixture.selection.enter(fixture.messages[0]);
    fixture.selection.toggle(fixture.messages[7]);
    await fixture.mount(tester);
    final gesture = await fixture.hold(tester, 2);
    await gesture.moveTo(fixture.point(tester, 5));
    await tester.pump();
    expect(fixture.selection.selectedIDs,
        {'row-0', 'row-2', 'row-3', 'row-4', 'row-5', 'row-7'});
    await gesture.moveTo(fixture.point(tester, 3));
    await tester.pump();
    expect(fixture.selection.selectedIDs, {'row-0', 'row-2', 'row-3', 'row-7'});
    await gesture.moveTo(fixture.point(tester, 1));
    await tester.pump();
    expect(fixture.selection.selectedIDs, {'row-0', 'row-1', 'row-2', 'row-7'});
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a selected start continuously clears and restores rows outside the shrinking range',
      (tester) async {
    final fixture = _DragFixture();
    addTearDown(() => fixture.dispose(tester));
    fixture.selection.enter(fixture.messages[0]);
    for (final index in [2, 3, 4, 7]) {
      fixture.selection.toggle(fixture.messages[index]);
    }
    await fixture.mount(tester);
    final gesture = await fixture.hold(tester, 3);
    await gesture.moveTo(fixture.point(tester, 5));
    await tester.pump();
    expect(fixture.selection.selectedIDs, {'row-0', 'row-2', 'row-7'});
    await gesture.moveTo(fixture.point(tester, 2));
    await tester.pump();
    expect(fixture.selection.selectedIDs, {'row-0', 'row-4', 'row-7'});
    await gesture.moveTo(fixture.point(tester, 2));
    await tester.pump();
    expect(fixture.selection.selectedIDs, {'row-0', 'row-4', 'row-7'},
        reason: 'repeated movement must not toggle already handled rows');
    await gesture.up();
  });

  testWidgets('drag ranges skip notification rows and can be moved upwards',
      (tester) async {
    final fixture = _DragFixture();
    addTearDown(() => fixture.dispose(tester));
    fixture.messages[3] = selectionMessage('row-3', contentType: 1001);
    fixture.selection.enter(fixture.messages[7]);
    await fixture.mount(tester);
    final gesture = await fixture.hold(tester, 5);
    await gesture.moveTo(fixture.point(tester, 1));
    await tester.pump();
    expect(fixture.selection.selectedIDs,
        {'row-1', 'row-2', 'row-4', 'row-5', 'row-7'});
    expect(fixture.selection.isSelected(fixture.messages[3]), isFalse);
    await gesture.up();
  });

  testWidgets(
      'normal drag still scrolls the selected list without changing selection',
      (tester) async {
    final fixture = _DragFixture(count: 30);
    addTearDown(() => fixture.dispose(tester));
    fixture.selection.enter(fixture.messages[0]);
    await fixture.mount(tester);
    final baseline = Set.of(fixture.selection.selectedIDs);
    await tester.drag(find.byKey(const ValueKey('selection-drag-list')),
        const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(fixture.scroll.offset, greaterThan(0));
    expect(fixture.selection.selectedIDs, baseline);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long press outside selection leaves the mode inactive',
      (tester) async {
    final fixture = _DragFixture();
    addTearDown(() => fixture.dispose(tester));
    await fixture.mount(tester);
    final gesture = await fixture.hold(tester, 2);
    await gesture.moveTo(fixture.point(tester, 5));
    await gesture.up();
    await tester.pump();
    expect(fixture.selection.active, isFalse);
    expect(fixture.selection.count, 0);
  });

  testWidgets('cancel during a drag prevents remaining movement from selecting',
      (tester) async {
    final fixture = _DragFixture();
    addTearDown(() => fixture.dispose(tester));
    fixture.selection.enter(fixture.messages[0]);
    await fixture.mount(tester);
    final gesture = await fixture.hold(tester, 2);
    fixture.selection.cancel();
    await tester.pump();
    await gesture.moveTo(fixture.point(tester, 5));
    await gesture.up();
    await tester.pump();
    expect(fixture.selection.active, isFalse);
    expect(fixture.selection.count, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'centered chat viewport drags through negative offsets and retains a lazy range anchor while paging',
      (tester) async {
    final messages =
        List.generate(40, (index) => selectionMessage('history-$index'));
    final scroll = ScrollController();
    final selection = MessageSelectionController(
      messages: () => messages,
      isClosed: () => false,
      onStart: () {},
      deleteMessages: (_) async => true,
      forwardMessages: (_, {required merged}) async => false,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      selection.dispose();
      scroll.dispose();
    });
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late StateSetter update;
    selection.enter(messages.last);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 320,
              child: MessageSelectionDragRegion(
                controller: selection,
                scrollController: scroll,
                child: StatefulBuilder(builder: (_, setState) {
                  update = setState;
                  final ids =
                      messages.map((message) => message.clientMsgID!).toList();
                  return ChatListView(
                    controller: scroll,
                    itemCount: messages.length,
                    messageIDs: ids,
                    loadOnInit: false,
                    hasMore: false,
                    findChildIndexCallback: (key) =>
                        key is ValueKey<String> && ids.contains(key.value)
                            ? ids.indexOf(key.value)
                            : null,
                    itemBuilder: (_, index) {
                      final message = messages[index];
                      return MessageSelectionRow(
                        key: ValueKey(message.clientMsgID!),
                        controller: selection,
                        message: message,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: ChatMessageContentAnchor(
                            messageID: message.clientMsgID!,
                            child: SizedBox(
                              key: ValueKey(
                                  'centered-content-${message.clientMsgID}'),
                              height: 64,
                              child: Text(message.clientMsgID!),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    scroll.jumpTo(600);
    await tester.pumpAndSettle();
    update(() => messages.insertAll(
        0, List.generate(80, (index) => selectionMessage('arrival-$index'))));
    selection.sync();
    await tester.pumpAndSettle();
    expect(scroll.position.minScrollExtent, lessThan(-300));
    scroll.jumpTo(-300);
    await tester.pumpAndSettle();
    expect(scroll.offset, lessThan(0));

    final origin = messages.firstWhere((message) {
      final content =
          find.byKey(ValueKey('centered-content-${message.clientMsgID}'));
      if (content.evaluate().isEmpty) return false;
      final center = tester.getCenter(content);
      return center.dy > 40 && center.dy < 280;
    }).clientMsgID!;
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('centered-content-$origin'))));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    expect(selection.selectedIDs, contains(origin));
    await gesture.moveTo(const Offset(180, 312));
    final initialOffset = scroll.offset;
    for (var frame = 0; frame < 60; frame++) {
      if (frame == 18) {
        update(() => messages.addAll(
            List.generate(20, (index) => selectionMessage('paged-$index'))));
        selection.sync();
      }
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(scroll.offset, lessThan(initialOffset - 700));
    expect(scroll.offset, lessThan(0));
    expect(find.byKey(ValueKey(origin)), findsNothing,
        reason: 'the original row has left the lazy viewport');
    expect(selection.selectedIDs, contains(origin),
        reason:
            'range selection keeps its message ID after its row is unloaded');
    expect(selection.count, greaterThan(8));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final pausedOffset = scroll.offset;
    final pausedSelection = selection.selectedIDs;
    await tester.pump(const Duration(milliseconds: 400));
    expect(scroll.offset, closeTo(pausedOffset, .01));
    expect(selection.selectedIDs, pausedSelection);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 400));
    expect(scroll.offset, closeTo(pausedOffset, .01));
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final reverse in [false, true]) {
    testWidgets(
        'edge dragging auto scrolls and release stops it (reverse=$reverse)',
        (tester) async {
      final fixture = _DragFixture(count: 60, reverse: reverse);
      addTearDown(() => fixture.dispose(tester));
      fixture.selection.enter(fixture.messages[0]);
      await fixture.mount(tester);
      final gesture = await fixture.hold(tester, 1);
      await gesture.moveTo(Offset(180, reverse ? 8 : _screen.height - 8));
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(fixture.scroll.offset, greaterThan(0));
      expect(fixture.selection.count, greaterThan(3));
      await gesture.up();
      await tester.pump();
      final offsetAfterRelease = fixture.scroll.offset;
      await tester.pump(const Duration(milliseconds: 400));
      expect(fixture.scroll.offset, closeTo(offsetAfterRelease, .01));
      expect(tester.takeException(), isNull);
    });
  }
}
