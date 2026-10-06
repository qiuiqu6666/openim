import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/announcements/group_announcement_banner.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final dark in [false, true]) {
    for (final dimensions in [(375.0, 1.0), (320.0, 2.0)]) {
      testWidgets(
          'warm announcement keeps entry geometry on first paint and updates / '
          'dark=$dark width=${dimensions.$1} scale=${dimensions.$2}',
          (tester) async {
        const text = '已经读过的群公告';
        SharedPreferences.setMockInitialValues({
          'group_announcement_read:user:group': text,
        });
        final prefs = await SharedPreferences.getInstance();
        final snapshot = ValueNotifier(_warmBanner(prefs, text: text));
        addTearDown(snapshot.dispose);
        final host = await _mountBannerSnapshot(tester, snapshot,
            dark: dark, width: dimensions.$1, scale: dimensions.$2);
        final row = find.byKey(const ValueKey('group-announcement-row'));
        final entry = find.byKey(const ValueKey('entry-below-announcement'));
        expect(row, findsOneWidget);
        final firstBounds = tester.getRect(row);
        final firstEntry = tester.getRect(entry).top;
        expect(firstEntry, greaterThan(0));
        _expectRowFits(tester, dimensions.$1);

        Future<void> expectStableFrame() async {
          await tester.pump();
          expect(tester.getRect(row), firstBounds);
          expect(tester.getRect(entry).top, firstEntry);
          expect(tester.takeException(), isNull);
        }

        await expectStableFrame();
        // An unchanged SDK refresh should not restart preference hydration.
        snapshot.value = _warmBanner(prefs, text: text);
        await expectStableFrame();
        snapshot.value = _warmBanner(prefs, text: text, version: '2');
        await expectStableFrame();
        const changedText = '新版本公告内容';
        await prefs.setString(
            'group_announcement_read:user:group', changedText);
        snapshot.value = _warmBanner(prefs, text: changedText, version: '3');
        await expectStableFrame();
        await expectStableFrame();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(host);
        expect(tester.getRect(row), firstBounds);
        expect(tester.getRect(entry).top, firstEntry);
        await expectStableFrame();
      });
    }
  }

  testWidgets('warm dismissed revision stays hidden until a newer announcement',
      (tester) async {
    const text = '被关闭的公告';
    SharedPreferences.setMockInitialValues({
      'group_announcement_dismissed:user:group': '1:$text',
      'group_announcement_read:user:group': text,
    });
    final prefs = await SharedPreferences.getInstance();
    final snapshot = ValueNotifier(_warmBanner(prefs, text: text));
    addTearDown(snapshot.dispose);
    final host = await _mountBannerSnapshot(tester, snapshot);
    final row = find.byKey(const ValueKey('group-announcement-row'));
    final entry = find.byKey(const ValueKey('entry-below-announcement'));
    expect(row, findsNothing);
    expect(tester.getRect(entry).top, 0);
    await tester.pump();
    expect(row, findsNothing);

    snapshot.value = _warmBanner(prefs, text: text);
    await tester.pump();
    expect(row, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host);
    expect(row, findsNothing);
    expect(tester.getRect(entry).top, 0);

    snapshot.value = _warmBanner(prefs, text: text, version: '2');
    await tester.pump();
    expect(row, findsOneWidget);
    final visibleTop = tester.getRect(entry).top;
    expect(visibleTop, greaterThan(0));
    await tester.pump();
    expect(tester.getRect(entry).top, visibleTop);
    expect(
        prefs.getString('group_announcement_dismissed:user:group'), '1:$text');
    expect(tester.takeException(), isNull);
  });

  testWidgets('warm visibility is scoped to the current user and group',
      (tester) async {
    const text = '相同公告正文';
    SharedPreferences.setMockInitialValues({
      'group_announcement_dismissed:user:group': '1:$text',
      'group_announcement_read:user:group': text,
      'group_announcement_read:other:group': text,
      'group_announcement_read:other:next': text,
      'group_announcement_dismissed:other:next': '1:$text',
    });
    final prefs = await SharedPreferences.getInstance();
    final snapshot = ValueNotifier(_warmBanner(prefs, text: text));
    addTearDown(snapshot.dispose);
    await _mountBannerSnapshot(tester, snapshot);
    final row = find.byKey(const ValueKey('group-announcement-row'));
    expect(row, findsNothing);
    snapshot.value = _warmBanner(prefs, text: text, userID: 'other');
    await tester.pump();
    expect(row, findsOneWidget);
    snapshot.value =
        _warmBanner(prefs, text: text, userID: 'other', groupID: 'next');
    await tester.pump();
    expect(row, findsNothing);
    snapshot.value = _warmBanner(prefs, text: text, version: '2');
    await tester.pump();
    expect(row, findsOneWidget);
    await tester.pump();
    expect(row, findsOneWidget);
    expect(find.text('群公告'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden announcement and sibling tooltip dispose cleanly',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'group_announcement_dismissed:user:group': ':notice',
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          GroupAnnouncementBanner(
            text: 'notice',
            groupID: 'group',
            userID: 'user',
          ),
          Tooltip(message: 'Sibling tooltip', child: Text('Sibling')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('Next page')),
    ));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Next page'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('announcement removed before preferences finish is safe',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(
      home: GroupAnnouncementBanner(
        text: 'notice',
        groupID: 'group',
        userID: 'user',
      ),
    ));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'normal width keeps the prefix intrinsic and close action at edge',
      (tester) async {
    await _mountVisibleBanner(tester, text: '公告内容');
    final prefix = find.byKey(const ValueKey('group-announcement-prefix'));
    final close = find.byKey(const ValueKey('group-announcement-close'));
    final prefixText = tester.widget<Text>(prefix);
    final painter = TextPainter(
      text: TextSpan(text: prefixText.data, style: prefixText.style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    expect(tester.getSize(prefix).width, closeTo(painter.width, .01));
    painter.dispose();
    expect(tester.getRect(prefix).left, 12);
    expect(tester.getRect(close).right, 375 - 12);
    expect(tester.getRect(close).width, 32);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final width in [320.0, 375.0]) {
      for (final scale in [1.0, 2.0, 4.0]) {
        testWidgets(
            'visible announcement fits / dark=$dark width=$width scale=$scale',
            (tester) async {
          await _mountVisibleBanner(
            tester,
            text: '这是一条长群公告，用于确认窄屏和大字号时内容仍受约束。',
            dark: dark,
            width: width,
            scale: scale,
          );
          expect(find.text('群公告'), findsNothing);
          _expectRowFits(tester, width);
          final close = find.byKey(const ValueKey('group-announcement-close'));
          expect(tester.getRect(close).right, closeTo(width - 12, .01));
          expect(tester.getRect(close).width, 32);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final width in [16.0, 40.0, 72.0, 140.0]) {
    testWidgets('very narrow announcement remains bounded / width=$width',
        (tester) async {
      await _mountVisibleBanner(tester, text: '公告内容', width: width, scale: 4);
      _expectRowFits(tester, width);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('visible announcement still opens and dismisses normally',
      (tester) async {
    const notice = '点击公告可以查看完整内容';
    await _mountVisibleBanner(tester, text: notice, width: 320, scale: 2);
    await tester.tap(find.byKey(const ValueKey('group-announcement-prefix')));
    await tester.pumpAndSettle();
    expect(find.text('群公告'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(find.text('群公告'), findsNothing);
    expect(find.byKey(const ValueKey('group-announcement-prefix')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-announcement-close')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('group-announcement-prefix')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getString('group_announcement_dismissed:user:group'), ':$notice');
    expect(prefs.getString('group_announcement_read:user:group'), notice);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long animated announcement clips inside its bounded viewport',
      (tester) async {
    await _mountVisibleBanner(
      tester,
      text: List.filled(30, '一段很长的群公告内容').join(' '),
      width: 320,
      scale: 2,
      disableAnimations: false,
    );
    await tester.pump(const Duration(milliseconds: 250));
    _expectRowFits(tester, 320);
    final content = find.byKey(const ValueKey('group-announcement-content'));
    expect(find.descendant(of: content, matching: find.byType(ClipRect)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

GroupAnnouncementBanner _warmBanner(SharedPreferences preferences,
        {required String text,
        String userID = 'user',
        String groupID = 'group',
        String version = '1'}) =>
    GroupAnnouncementBanner(
      text: text,
      userID: userID,
      groupID: groupID,
      version: version,
      preferences: preferences,
    );

Future<Widget> _mountBannerSnapshot(
  WidgetTester tester,
  ValueListenable<GroupAnnouncementBanner> snapshot, {
  bool dark = false,
  double width = 375,
  double scale = 1,
}) async {
  final previousDark = Styles.isDark;
  Styles.isDark = dark;
  addTearDown(() => Styles.isDark = previousDark);
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final host = MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: ValueListenableBuilder<GroupAnnouncementBanner>(
        valueListenable: snapshot,
        builder: (context, banner, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            banner,
            const SizedBox(
                key: ValueKey('entry-below-announcement'), height: 44),
          ],
        ),
      ),
    ),
  );
  await tester.pumpWidget(host);
  return host;
}

Future<void> _mountVisibleBanner(
  WidgetTester tester, {
  required String text,
  bool dark = false,
  double width = 375,
  double scale = 1,
  bool disableAnimations = true,
}) async {
  final previousDark = Styles.isDark;
  Styles.isDark = dark;
  addTearDown(() => Styles.isDark = previousDark);
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    // Already read, but not dismissed: show the banner without an automatic sheet.
    'group_announcement_read:user:group': text,
  });
  await DataSp.init();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: GroupAnnouncementBanner(
          text: text,
          groupID: 'group',
          userID: 'user',
        ),
      ),
    ),
  ));
  if (disableAnimations) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
  // The full announcement sheet uses MatchTextView's ScreenUtil-based width.
  ScreenUtil.init(tester.element(find.byType(GroupAnnouncementBanner)),
      designSize: const Size(375, 812));
}

void _expectRowFits(WidgetTester tester, double width) {
  final row = find.byKey(const ValueKey('group-announcement-row'));
  expect(row, findsOneWidget);
  final rowBounds = tester.getRect(row);
  expect(rowBounds.left, greaterThanOrEqualTo(0));
  expect(rowBounds.right, lessThanOrEqualTo(width));
  for (final name in ['prefix', 'content', 'close']) {
    final bounds =
        tester.getRect(find.byKey(ValueKey('group-announcement-$name')));
    expect(bounds.left, greaterThanOrEqualTo(rowBounds.left - .01));
    expect(bounds.right, lessThanOrEqualTo(rowBounds.right + .01));
  }
}
