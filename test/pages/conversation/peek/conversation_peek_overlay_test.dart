import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_layout.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_overlay.dart';
import 'package:openim/pages/official_account/official_account_chrome_tokens.dart';
import 'package:openim/pages/official_account/widgets/official_account_name_label.dart';
import 'package:openim_common/openim_common.dart';

class _Harness {
  late BuildContext context;
  bool allowOpen = true;
  bool returned = false;
  int opened = 0;
  int dismissed = 0;
  int? action;
  int itemCount = 6;
  String? userID;
  String? ex;
  bool isSingleChat = true;
  Widget messageContent = const Center(child: Text('Message content'));

  Future<void> show() async {
    returned = false;
    final completion = ConversationPeekOverlay.show(
      context: context,
      displayName: 'Conversation name',
      userID: userID,
      ex: ex,
      isSingleChat: isSingleChat,
      headerSubtitle:
          const Text('Online', style: TextStyle(fontSize: 11, height: 1.1)),
      messageContent: messageContent,
      menuItemCount: itemCount,
      menuDividerCount: 1,
      canOpenChat: () => allowOpen,
      onOpenChat: () => opened++,
      onDismiss: () => dismissed++,
      menuBuilder: (context, padding, dismiss) => Container(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < itemCount; index++)
              InkWell(
                key: ValueKey('action-$index'),
                onTap: () {
                  action = index;
                  dismiss();
                },
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: padding),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_outlined, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text('Action $index',
                              style: const TextStyle(fontSize: 15))),
                    ],
                  ),
                ),
              ),
            const Divider(height: 1, thickness: .5),
          ],
        ),
      ),
    );
    await completion;
    returned = true;
  }
}

Future<_Harness> _mount(WidgetTester tester,
    {bool dark = false,
    Size size = const Size(375, 812),
    double textScale = 1,
    bool disableAnimations = false}) async {
  final harness = _Harness();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0089FF),
            brightness: dark ? Brightness.dark : Brightness.light)),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: const EdgeInsets.only(top: 24, bottom: 34),
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: Builder(builder: (context) {
      harness.context = context;
      return const Scaffold(body: Center(child: Text('Underlying page')));
    }),
  ));
  addTearDown(() async {
    if (harness.context.mounted) {
      Navigator.of(harness.context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
    }
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  return harness;
}

Finder get _card => find.byKey(const ValueKey('conversation-peek-card'));
Finder get _menu =>
    find.byKey(const ValueKey('conversation-peek-menu-viewport'));

void main() {
  testWidgets(
      'peek identity preserves its name and displays the official badge',
      (tester) async {
    final harness = await _mount(tester);
    harness.userID = '99Pay';
    final completion = harness.show();
    await tester.pumpAndSettle();
    final label = tester.widget<OfficialAccountNameLabel>(
        find.byType(OfficialAccountNameLabel));
    expect(label.name, 'Conversation name');
    expect(label.userID, '99Pay');
    final badge = find.byWidgetPredicate((widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName ==
            OfficialAccountChromeTokens.badgeAsset);
    expect(badge, findsOneWidget);
    expect(tester.getRect(_card).contains(tester.getCenter(badge)), isTrue);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('action-0')));
    await tester.pumpAndSettle();
    await completion;
  });

  test('normal layout retains the reference percentages and menu allowance',
      () {
    final metrics = ConversationPeekLayout.resolve(
      constraints: const BoxConstraints.tightFor(width: 375, height: 754),
      screenWidth: 375,
      menuItemCount: 6,
      menuDividerCount: 1,
    );
    expect(metrics.cardWidth, closeTo(347.25, .001));
    expect(metrics.cardRadius, closeTo(21.75, .001));
    expect(metrics.previewHeight, closeTo(441.5424, .001));
    expect(metrics.menuWidth, 180);
    expect(metrics.menuItemVerticalPadding, closeTo(9.048, .001));
    expect(metrics.menuNeedsScroll, isFalse);
  });

  test('large text and small windows reserve space for menu scrolling', () {
    final metrics = ConversationPeekLayout.resolve(
      constraints: const BoxConstraints.tightFor(width: 320, height: 182),
      screenWidth: 320,
      menuItemCount: 6,
      menuDividerCount: 1,
      textScaler: const TextScaler.linear(2),
    );
    expect(metrics.previewHeight, 0);
    expect(metrics.menuNeedsScroll, isTrue);
    expect(
        metrics.menuViewportHeight +
            metrics.gap +
            metrics.topPadding +
            metrics.bottomPadding,
        closeTo(182, .001));
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final dark in [false, true]) {
      testWidgets('reference placement, surface and backdrop ($platform/$dark)',
          (tester) async {
        final harness = await _mount(tester, dark: dark);
        final completion = harness.show();
        await tester.pumpAndSettle();
        final card = tester.getRect(_card);
        final menu = tester.getRect(_menu);
        expect(card.width, closeTo(347.25, .01));
        expect(card.height, closeTo(441.5424, .01));
        expect(menu.width, 180);
        expect(menu.right, closeTo(card.right, .01));
        expect(menu.top - card.bottom, closeTo(9.048, .01));
        expect(menu.bottom, closeTo(812 - 34 - 12.064, .01));
        expect(find.byType(BackdropFilter),
            platform == TargetPlatform.android ? findsNothing : findsOneWidget);
        expect(find.ancestor(of: _card, matching: find.byType(ScaleTransition)),
            findsNothing);
        final container = tester.widget<Container>(
            find.descendant(of: _card, matching: find.byType(Container)).first);
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color,
            dark ? AppTokens.backgroundDark : AppTokens.surfaceLight);
        expect((decoration.borderRadius! as BorderRadius).topLeft.x,
            closeTo(21.75, .01));
        final title = tester.widget<Text>(find.text('Conversation name'));
        expect(title.style!.color, AppTokens.textPrimary(dark: dark));
        expect(title.maxLines, 1);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('action-0')));
        await tester.pumpAndSettle();
        await tester.pump();
        expect(_card, findsNothing);
        expect(harness.returned, isTrue);
        await completion;
        expect(harness.dismissed, 1);
        expect(harness.opened, 0);
      }, variant: TargetPlatformVariant({platform}));
    }
  }

  testWidgets('the show Future waits for the 220 ms fade out', (tester) async {
    final harness = await _mount(tester);
    final completion = harness.show();
    await tester.pump();
    final fade =
        find.ancestor(of: _card, matching: find.byType(FadeTransition));
    expect(tester.widget<FadeTransition>(fade.first).opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 110));
    expect(tester.widget<FadeTransition>(fade.first).opacity.value,
        allOf(greaterThan(0), lessThan(1)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Message content'));
    await tester.pump();
    expect(harness.opened, 1);
    expect(harness.returned, isFalse);
    await tester.pump(const Duration(milliseconds: 110));
    expect(harness.returned, isFalse);
    await tester.pumpAndSettle();
    await completion;
    expect(harness.returned, isTrue);
    expect(harness.dismissed, 1);
    expect(_card, findsNothing);
  });

  testWidgets('opening checks current loader readiness without rebuilding',
      (tester) async {
    final harness = await _mount(tester);
    harness.allowOpen = false;
    final completion = harness.show();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Message content'));
    await tester.pumpAndSettle();
    expect(_card, findsOneWidget);
    expect(harness.opened, 0);
    harness.allowOpen = true;
    await tester.tap(find.text('Message content'));
    await tester.pumpAndSettle();
    await completion;
    expect(harness.opened, 1);
    expect(harness.dismissed, 1);
  });

  testWidgets('a content retry button keeps its own tap handling',
      (tester) async {
    final harness = await _mount(tester);
    var retries = 0;
    harness.allowOpen = false;
    harness.messageContent = Center(
        child:
            TextButton(onPressed: () => retries++, child: const Text('Retry')));
    final completion = harness.show();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(harness.opened, 0);
    expect(_card, findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await completion;
  });

  testWidgets('duplicate presentation is ignored and next preview can open',
      (tester) async {
    final harness = await _mount(tester);
    final completion = harness.show();
    await tester.pumpAndSettle();
    var duplicateOpen = 0;
    await ConversationPeekOverlay.show(
      context: harness.context,
      displayName: 'Duplicate',
      messageContent: const SizedBox(),
      menuBuilder: (_, __, ___) => const SizedBox(),
      menuItemCount: 0,
      menuDividerCount: 0,
      onOpenChat: () => duplicateOpen++,
    );
    expect(find.text('Duplicate'), findsNothing);
    expect(_card, findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await completion;
    final nextCompletion = harness.show();
    await tester.pumpAndSettle();
    expect(_card, findsOneWidget);
    Navigator.of(harness.context).pop();
    await tester.pumpAndSettle();
    await nextCompletion;
    expect(harness.dismissed, 2);
    expect(duplicateOpen, 0);
  });

  for (final size in [const Size(320, 480), const Size(240, 240)]) {
    testWidgets(
        'large text in a small window keeps menu actions reachable $size',
        (tester) async {
      final harness = await _mount(tester, size: size, textScale: 2);
      final completion = harness.show();
      await tester.pumpAndSettle();
      expect(tester.getRect(_menu).right, lessThanOrEqualTo(size.width));
      expect(tester.getRect(_menu).bottom, lessThanOrEqualTo(size.height - 34));
      expect(tester.takeException(), isNull);
      final menuScroll = find.descendant(
          of: _menu, matching: find.byType(SingleChildScrollView));
      await tester.drag(menuScroll, const Offset(0, -600));
      await tester.pumpAndSettle();
      final lastAction = find.byKey(const ValueKey('action-5'));
      await tester.ensureVisible(lastAction);
      await tester.pumpAndSettle();
      final visibleAction =
          tester.getRect(lastAction).intersect(tester.getRect(_menu));
      expect(visibleAction.height, greaterThan(0));
      await tester.tapAt(visibleAction.center);
      await tester.pumpAndSettle();
      await completion;
      expect(harness.action, 5);
      expect(harness.opened, 0);
      expect(harness.dismissed, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion closes normally without a timed transition',
      (tester) async {
    final harness = await _mount(tester, disableAnimations: true);
    final completion = harness.show();
    await tester.pumpAndSettle();
    Navigator.of(harness.context).pop();
    await tester.pumpAndSettle();
    await completion;
    expect(harness.returned, isTrue);
    expect(harness.dismissed, 1);
    expect(_card, findsNothing);
  });
}
