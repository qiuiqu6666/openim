import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/chat/chat_list_viewport.dart';

class _ChatFixture extends StatefulWidget {
  const _ChatFixture({
    super.key,
    required this.position,
    required this.scroll,
    this.count = 4000,
  });

  final ChatListPositionController position;
  final ScrollController scroll;
  final int count;

  @override
  State<_ChatFixture> createState() => _ChatFixtureState();
}

class _ChatFixtureState extends State<_ChatFixture> {
  late List<String> ids = List.generate(widget.count, (index) => 'm-$index');
  int builds = 0;
  List<String> read = [];
  ChatListPositionController? replacementPosition;

  void replace(List<String> next) => setState(() => ids = next);

  void replacePosition(ChatListPositionController next) =>
      setState(() => replacementPosition = next);

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: const ValueKey('viewport'),
            width: 420,
            height: 600,
            child: ChatListViewport(
              positionController: replacementPosition ?? widget.position,
              controller: widget.scroll,
              padding: const EdgeInsets.only(top: 10),
              messageIDs: ids,
              itemCount: ids.length,
              onViewportChanged: (nextRead, _) => read = nextRead,
              findChildIndexCallback: (key) {
                final index = ids.indexOf((key as ValueKey<String>).value);
                return index < 0 ? null : index;
              },
              itemBuilder: (_, index) {
                builds++;
                final id = ids[index];
                final number = int.tryParse(id.replaceFirst('m-', '')) ?? 1;
                return SizedBox(
                  key: ValueKey(id),
                  height: 38 + number % 7 * 21,
                  child: Text(id),
                );
              },
            ),
          ),
        ),
      );
}

Future<_ChatFixtureState> _mount(
  WidgetTester tester,
  ChatListPositionController position,
  ScrollController scroll, {
  int count = 4000,
}) async {
  final key = GlobalKey<_ChatFixtureState>();
  await tester.pumpWidget(_ChatFixture(
    key: key,
    position: position,
    scroll: scroll,
    count: count,
  ));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    position.dispose();
    scroll.dispose();
  });
  return key.currentState!;
}

void _expectVisible(WidgetTester tester, String id) {
  final finder = find.byKey(ValueKey(id)).first;
  expect(finder, findsOneWidget);
  final row = tester.getRect(finder);
  final viewport = tester.getRect(find.byKey(const ValueKey('viewport')));
  expect(row.top, greaterThanOrEqualTo(viewport.top - 0.5));
  expect(row.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
}

Future<bool> _jump(
    WidgetTester tester, ChatListPositionController position, String id) async {
  final completion = position.jumpToMessage(id);
  await tester.pumpAndSettle();
  return completion;
}

void main() {
  testWidgets('a far lazy variable-height message paints without a height scan',
      (tester) async {
    final position = ChatListPositionController();
    final scroll = ScrollController();
    final fixture = await _mount(tester, position, scroll);
    expect(find.byKey(const ValueKey('m-3800')), findsNothing);
    fixture.builds = 0;
    expect(await _jump(tester, position, 'm-3800'), isTrue);
    _expectVisible(tester, 'm-3800');
    expect(fixture.read, contains('m-3800'));
    expect(fixture.builds, lessThan(200));
  });

  testWidgets('arrivals and older pages retain the positioned message',
      (tester) async {
    final position = ChatListPositionController();
    final scroll = ScrollController();
    final fixture = await _mount(tester, position, scroll);
    expect(await _jump(tester, position, 'm-2000'), isTrue);
    final top =
        tester.getTopLeft(find.byKey(const ValueKey('m-2000')).first).dy;
    fixture.replace(['arrival', ...fixture.ids]);
    await tester.pumpAndSettle();
    _expectVisible(tester, 'm-2000');
    expect(tester.getTopLeft(find.byKey(const ValueKey('m-2000')).first).dy,
        closeTo(top, 0.5));
    fixture.replace([...fixture.ids, 'older-page']);
    await tester.pumpAndSettle();
    _expectVisible(tester, 'm-2000');
    expect(tester.getTopLeft(find.byKey(const ValueKey('m-2000')).first).dy,
        closeTo(top, 0.5));
  });

  testWidgets('same-frame edge additions do not redirect a pending date jump',
      (tester) async {
    final position = ChatListPositionController();
    final scroll = ScrollController();
    final fixture = await _mount(tester, position, scroll);
    final pending = position.jumpToMessage('m-1800');
    fixture.replace(['arrival', ...fixture.ids, 'older-page']);
    await tester.pumpAndSettle();
    expect(await pending, isTrue);
    _expectVisible(tester, 'm-1800');
    expect(fixture.read, contains('m-1800'));
  });

  testWidgets('the oldest short row stays visible in a long history window',
      (tester) async {
    final position = ChatListPositionController();
    final scroll = ScrollController();
    final fixture = await _mount(tester, position, scroll, count: 3998);
    expect(find.byKey(const ValueKey('m-3997')), findsNothing);
    fixture.builds = 0;
    expect(await _jump(tester, position, 'm-3997'), isTrue);
    _expectVisible(tester, 'm-3997');
    expect(fixture.read, contains('m-3997'));
    expect(fixture.builds, lessThan(200));
  });

  testWidgets('short date windows position either edge with reduced motion',
      (tester) async {
    final position = ChatListPositionController();
    final scroll = ScrollController();
    final fixture = await _mount(tester, position, scroll, count: 4);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    expect(await _jump(tester, position, 'm-3'), isTrue);
    _expectVisible(tester, 'm-3');
    expect(await _jump(tester, position, 'm-0'), isTrue);
    _expectVisible(tester, 'm-0');
    expect(fixture.read, contains('m-0'));
    expect(scroll.position.isScrollingNotifier.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing IDs fail without moving the reader', (tester) async {
    final position = ChatListPositionController();
    final scroll = ScrollController();
    await _mount(tester, position, scroll);
    expect(await _jump(tester, position, 'm-2500'), isTrue);
    final top =
        tester.getTopLeft(find.byKey(const ValueKey('m-2500')).first).dy;
    expect(await _jump(tester, position, 'missing'), isFalse);
    expect(tester.getTopLeft(find.byKey(const ValueKey('m-2500')).first).dy,
        closeTo(top, 0.5));
  });

  testWidgets(
      'new requests cancel the old jump and latest scrolling still works',
      (tester) async {
    final position = ChatListPositionController();
    final scroll = ScrollController();
    final fixture = await _mount(tester, position, scroll);
    final first = position.jumpToMessage('m-3000');
    final second = position.jumpToMessage('m-1200');
    expect(await first, isFalse);
    await tester.pumpAndSettle();
    expect(await second, isTrue);
    _expectVisible(tester, 'm-1200');
    fixture.builds = 0;
    expect(await _jump(tester, position, 'm-2800'), isTrue);
    _expectVisible(tester, 'm-2800');
    expect(fixture.builds, lessThan(200));
    fixture.builds = 0;
    scroll.jumpTo(scroll.position.minScrollExtent);
    await tester.pumpAndSettle();
    _expectVisible(tester, 'm-0');
    expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 0.5));
    expect(fixture.read, contains('m-0'));
    expect(fixture.builds, lessThan(200));
  });

  testWidgets('removing a target cancels positioning before it reports success',
      (tester) async {
    final position = ChatListPositionController();
    final scroll = ScrollController();
    final fixture = await _mount(tester, position, scroll);
    final pending = position.jumpToMessage('m-2000');
    fixture.replace(fixture.ids.where((id) => id != 'm-2000').toList());
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cancel, controller replacement, and disposal reject pending jumps',
      (tester) async {
    final position = ChatListPositionController();
    final scroll = ScrollController();
    final fixture = await _mount(tester, position, scroll);
    final cancelled = position.jumpToMessage('m-2000');
    position.cancel();
    expect(await cancelled, isFalse);
    await tester.pumpAndSettle();
    final replaced = position.jumpToMessage('m-2200');
    final replacement = ChatListPositionController();
    addTearDown(replacement.dispose);
    fixture.replacePosition(replacement);
    await tester.pumpAndSettle();
    expect(await replaced, isFalse);
    expect(await position.jumpToMessage('m-2500'), isFalse);
    final disposed = replacement.jumpToMessage('m-2600');
    replacement.dispose();
    expect(await disposed, isFalse);
    await tester.pumpAndSettle();
    expect(await replacement.jumpToMessage('m-100'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmounting completes a pending jump safely', (tester) async {
    final position = ChatListPositionController();
    final scroll = ScrollController();
    await _mount(tester, position, scroll);
    final pending = position.jumpToMessage('m-2000');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(await pending, isFalse);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
