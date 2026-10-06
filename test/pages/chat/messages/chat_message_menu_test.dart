import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

import 'support/chat_message_menu_test_host.dart';

bool _paintedMenuColor(Widget widget) {
  const color = Color(0xFF4C4C4C);
  return widget is Material && widget.color == color ||
      widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == color ||
      widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == color;
}

void _expectWithin(Rect inner, Rect outer) {
  expect(inner.left, greaterThanOrEqualTo(outer.left - .1));
  expect(inner.top, greaterThanOrEqualTo(outer.top - .1));
  expect(inner.right, lessThanOrEqualTo(outer.right + .1));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + .1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brightness in Brightness.values) {
    for (final outgoing in [false, true]) {
      for (final count in [5, 7]) {
        testWidgets(
            '$count actions use five columns with icons above labels ($brightness, outgoing=$outgoing)',
            (tester) async {
          final harness = MenuTestHarness();
          await harness.mount(tester,
              menus: harness.menus(count),
              outgoing: outgoing,
              brightness: brightness,
              anchor: Offset(outgoing ? 179 : 16, 300),
              realFonts: true);
          await harness.open(tester);
          final panel = tester.getRect(find.byKey(menuPanelKey));
          expect(panel.width, closeTo(300, .1));
          expect(find.byWidgetPredicate(_paintedMenuColor), findsWidgets);
          final cells = <Rect>[];
          for (var i = 0; i < count; i++) {
            final action = menuTestActions[i];
            final cell = menuAction(action.id);
            final rect = tester.getRect(cell);
            cells.add(rect);
            _expectWithin(rect, panel);
            expect(rect.width, closeTo(56, 1));
            expect(rect.height, greaterThanOrEqualTo(52));
            final icon = find.descendant(
                of: cell, matching: find.byType(ChatMessageMenuIcon));
            expect(icon, findsOneWidget);
            expect(tester.widget<ChatMessageMenuIcon>(icon).action, action.id);
            expect(tester.getSize(icon), const Size(22, 22));
            final label =
                find.descendant(of: cell, matching: find.byType(Text));
            expect(label, findsOneWidget);
            expect(tester.widget<Text>(label).style?.fontFamily,
                'ChatMenuPreviewFont');
            expect(tester.getRect(icon).bottom,
                lessThanOrEqualTo(tester.getRect(label).top));
            expect(tester.getRect(icon).center.dx,
                closeTo(tester.getRect(label).center.dx, 1));
          }
          for (var i = 0; i < 5; i++) {
            expect(cells[i].top, closeTo(cells.first.top, .1));
            if (i > 0) expect(cells[i].left, greaterThan(cells[i - 1].left));
          }
          if (count == 7) {
            expect(cells[5].top, greaterThanOrEqualTo(cells[0].bottom));
            expect(cells[5].left, closeTo(cells[0].left, .1));
            expect(cells[6].left, closeTo(cells[1].left, .1));
            expect(cells[6].top, closeTo(cells[5].top, .1));
            final deleteLabel = find.descendant(
                of: menuAction('delete'), matching: find.byType(Text));
            expect(tester.widget<Text>(deleteLabel).style?.color,
                const Color(0xFFFF747C));
          }
          final copyLabel = find.descendant(
              of: menuAction('copyMessage'), matching: find.byType(Text));
          expect(tester.widget<Text>(copyLabel).style?.color, Colors.white);
          final arrow = tester
              .getRect(find.byKey(const ValueKey('chat-message-menu-arrow')));
          final message = tester.getRect(find.byKey(menuBubbleKey));
          expect(
              arrow.center.dx, inInclusiveRange(message.left, message.right));
          expect(panel.bottom <= message.top || panel.top >= message.bottom,
              isTrue);
          expect(find.text('👍'), findsNothing);
          expect(find.text('❤️'), findsNothing);
          if (count == 7) {
            await harness.screenshot(tester,
                '${brightness.name}-${outgoing ? 'outgoing' : 'incoming'}');
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('action closes the menu before invoking the existing callback',
      (tester) async {
    final harness = MenuTestHarness();
    await harness.mount(tester, menus: harness.menus(7));
    await harness.open(tester);
    await tester.tap(menuAction('copyMessage'));
    await settleMenu(tester);
    expect(harness.closedBeforeAction, isTrue);
    expect(harness.selected, ['copyMessage']);
    expect(find.byKey(menuPanelKey), findsNothing);
    expect(harness.controller.menuIsShowing, isFalse);
    expect(harness.messageTaps, 0);
    expect(harness.backgroundTaps, 0);
  });

  testWidgets('every reference action invokes only its own existing callback',
      (tester) async {
    final harness = MenuTestHarness();
    await harness.mount(tester, menus: harness.menus(8));
    for (final action in menuTestActions) {
      await harness.open(tester);
      await tester.tap(menuAction(action.id));
      await settleMenu(tester);
      expect(harness.closedBeforeAction, isTrue);
      expect(find.byKey(menuPanelKey), findsNothing);
      expect(harness.selected.last, action.id);
    }
    expect(harness.selected, menuTestActions.map((action) => action.id));
    expect(harness.messageTaps, 0);
  });

  testWidgets(
      'legacy menus retain their text and callback without an action ID',
      (tester) async {
    final harness = MenuTestHarness();
    var selected = false;
    await harness.mount(tester, menus: [
      PopMenuInfo(
          text: 'Existing custom action',
          iconWidget: const Icon(Icons.more_horiz),
          onTap: () => selected = true)
    ]);
    await harness.open(tester);
    expect(find.text('Existing custom action'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-message-menu-action-0')));
    await settleMenu(tester);
    expect(selected, isTrue);
    expect(find.byKey(menuPanelKey), findsNothing);
  });

  testWidgets('outside tap dismisses without activating the message underneath',
      (tester) async {
    final harness = MenuTestHarness();
    await harness.mount(tester, menus: harness.menus(5));
    await harness.open(tester);
    await tester.tapAt(tester.getRect(find.byKey(menuBubbleKey)).center);
    await settleMenu(tester);
    expect(find.byKey(menuPanelKey), findsNothing);
    expect(harness.messageTaps, 0);
    expect(harness.backgroundTaps, 0);
    expect(harness.selected, isEmpty);
    expect(harness.controller.menuIsShowing, isFalse);
  });

  testWidgets('controller hide closes the open menu and can reopen it',
      (tester) async {
    final harness = MenuTestHarness();
    await harness.mount(tester, menus: harness.menus(5));
    await harness.open(tester);
    harness.controller.hideMenu();
    await settleMenu(tester);
    expect(find.byKey(menuPanelKey), findsNothing);
    harness.controller.showMenu();
    await settleMenu(tester);
    expect(find.byKey(menuPanelKey), findsOneWidget);
    expect(harness.controller.menuIsShowing, isTrue);
  });

  testWidgets('system back closes only the menu and retains the chat page',
      (tester) async {
    final harness = MenuTestHarness();
    await harness.mount(tester, menus: harness.menus(5));
    await harness.open(tester);
    await tester.binding.handlePopRoute();
    await settleMenu(tester);
    expect(find.byKey(menuPanelKey), findsNothing);
    expect(find.byKey(menuBubbleKey), findsOneWidget);
    expect(harness.controller.menuIsShowing, isFalse);
    expect(harness.selected, isEmpty);
  });

  testWidgets('another route closes the menu and returning does not reopen it',
      (tester) async {
    final harness = MenuTestHarness();
    await harness.mount(tester, menus: harness.menus(5));
    await harness.open(tester);
    harness.navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Covered route'))));
    await settleMenu(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(menuPanelKey, skipOffstage: false), findsNothing);
    expect(harness.controller.menuIsShowing, isFalse);
    harness.navigator.currentState!.pop();
    await settleMenu(tester);
    await tester.pumpAndSettle();
    expect(find.text('Covered route'), findsNothing);
    expect(find.byKey(menuPanelKey), findsNothing);
    expect(find.byKey(menuBubbleKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmounting a message removes its menu without leaving a barrier',
      (tester) async {
    final harness = MenuTestHarness();
    await harness.mount(tester, menus: harness.menus(5));
    await harness.open(tester);
    harness.showMessage.value = false;
    await settleMenu(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(menuPanelKey), findsNothing);
    expect(
        find.byKey(const ValueKey('chat-message-menu-dismiss')), findsNothing);
    expect(harness.controller.menuIsShowing, isFalse);
    await tester.tapAt(const Offset(40, 400));
    expect(harness.backgroundTaps, 1);
    expect(tester.takeException(), isNull);
  });

  for (final anchor in [
    const Offset(0, 26),
    const Offset(140, 520),
  ]) {
    testWidgets('menu respects viewport edges and the keyboard at $anchor',
        (tester) async {
      final harness = MenuTestHarness();
      await harness.mount(tester,
          menus: harness.menus(7),
          anchor: anchor,
          screen: const Size(320, 812),
          keyboardHeight: 260,
          textScaler: TextScaler.linear(2));
      await harness.open(tester);
      final panel = tester.getRect(find.byKey(menuPanelKey));
      _expectWithin(panel, const Rect.fromLTRB(12, 36, 308, 540));
      for (final action in menuTestActions.take(7)) {
        final cell = menuAction(action.id);
        _expectWithin(tester.getRect(cell), panel);
        final label = find.descendant(of: cell, matching: find.byType(Text));
        _expectWithin(tester.getRect(label), tester.getRect(cell));
        expect(cell.hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('more than ten actions page horizontally with ten on each page',
      (tester) async {
    final harness = MenuTestHarness();
    await harness.mount(tester, menus: harness.menus(13));
    await harness.open(tester);
    expect(menuAction('replyMessage').hitTestable(), findsOneWidget);
    expect(menuAction('extra-10').hitTestable(), findsOneWidget);
    expect(menuAction('extra-11').hitTestable(), findsNothing);
    expect(menuAction('delete').hitTestable(), findsNothing);
    final pager = find.descendant(
        of: find.byKey(menuPanelKey),
        matching: find.byWidgetPredicate((widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal));
    expect(pager, findsOneWidget);
    await tester.drag(pager, const Offset(-280, 0));
    await settleMenu(tester);
    expect(menuAction('extra-11').hitTestable(), findsOneWidget);
    expect(menuAction('extra-12').hitTestable(), findsOneWidget);
    expect(menuAction('delete').hitTestable(), findsOneWidget);
    expect(menuAction('replyMessage').hitTestable(), findsNothing);
    await tester.tap(menuAction('extra-12'));
    await settleMenu(tester);
    expect(harness.selected, ['extra-12']);
    expect(harness.closedBeforeAction, isTrue);
    expect(find.byKey(menuPanelKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long pressing a message preserves composer focus and selection',
      (tester) async {
    final harness = MenuTestHarness();
    await harness.mount(tester,
        menus: harness.menus(5),
        composer: true,
        anchor: const Offset(16, 220),
        keyboardHeight: 300);
    await tester.enterText(
        find.byKey(const ValueKey('menu-test-input')), 'An unfinished draft');
    harness.input.selection =
        const TextSelection(baseOffset: 3, extentOffset: 11);
    await tester.pump();
    final before = harness.input.value;
    expect(harness.inputFocus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await harness.open(tester);
    expect(harness.inputFocus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(harness.input.value, before);
    harness.controller.hideMenu();
    await settleMenu(tester);
    expect(harness.inputFocus.hasFocus, isTrue);
    expect(harness.input.value, before);
    expect(tester.takeException(), isNull);
  });
}
