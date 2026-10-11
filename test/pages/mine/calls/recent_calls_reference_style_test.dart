import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/secondary/calls/recent_call_tile.dart';
import 'package:openim/pages/mine/secondary/calls/recent_call_tokens.dart';
import 'package:openim/pages/mine/secondary/calls/recent_calls_page.dart';
import 'package:openim/pages/mine/secondary/calls/widgets/recent_call_icons.dart';
import 'package:openim_common/openim_common.dart';

import 'recent_call_test_support.dart';
import 'recent_calls_ui_host.dart';

const _preview = bool.fromEnvironment('RECENT_CALLS_PREVIEW');
const _boundary = ValueKey('recent-calls-preview');
Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_preview) return;
  await tester.runAsync(() async {
    final context = tester.element(find.byType(RecentCallsPage));
    await Future.wait(tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => precacheImage(image.image, context)));
  });
  await tester.pump();
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
  boundary.markNeedsPaint();
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/previews/recent-calls/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeRecentCallsUi();
    if (_preview) {
      final font = FontLoader('RecentCallsPreview');
      font.addFont(File('C:/Windows/Fonts/msyh.ttc')
          .readAsBytes()
          .then((data) => ByteData.sublistView(data)));
      await font.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(File(
              'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then((data) => ByteData.sublistView(data)));
      await icons.load();
    }
  });
  tearDown(Get.reset);

  for (final dark in [false, true]) {
    testWidgets('99chat header, media art and full-width editing rows ($dark)',
        (tester) async {
      final box = RecentCallMemoryBox()
        ..backingMap['account-a'] = [
          callFixture(nickname: '阿明', room: 'audio'),
          callFixture(
              nickname: '小林',
              room: 'video',
              type: 'video',
              incoming: true,
              success: false,
              state: 'missed'),
          callFixture(
              nickname: '周末一起去旅行的朋友',
              room: 'long',
              incoming: true,
              success: false,
              state: 'rejected'),
        ];
      final cache = CacheController(
          accountIDProvider: () => 'account-a', boxOpener: () async => box);
      try {
        await mountRecentCalls(
            tester,
            RepaintBoundary(
                key: _boundary, child: RecentCallsPage(cacheController: cache)),
            dark: dark,
            fontFamily: _preview ? 'RecentCallsPreview' : null);
        await tester.pumpAndSettle();
        expect(find.text('编辑'), findsOneWidget);
        expect(find.byIcon(Icons.edit_outlined), findsNothing);
        expect(find.byIcon(Icons.add_call), findsNothing);
        expect(find.byType(RecentNewCallIcon), findsOneWidget);
        final first = _key('recent-call-room:audio');
        expect(tester.getRect(first).left, 0);
        expect(tester.getSize(first).width, 375);
        expect(tester.getSize(first).height,
            inInclusiveRange(RecentCallTokens.rowMinHeight, 90));
        final media = tester
            .widgetList<RecentCallMediaIcon>(find.byType(RecentCallMediaIcon))
            .toList();
        expect(media.map((icon) => icon.video), [false, true, false]);
        expect(
            media.every(
                (icon) => icon.color == AppTokens.textSecondary(dark: dark)),
            isTrue);
        expect(
            tester
                .widgetList<Divider>(find.byType(Divider))
                .every((divider) => divider.indent == 88),
            isTrue);
        await _capture(tester, dark ? 'dark-normal' : 'light-normal');
        await tester.tap(_key('recent-calls-edit'));
        await tester.pumpAndSettle();
        expect(find.text('删除全部'), findsOneWidget);
        expect(find.text('完成'), findsOneWidget);
        expect(tester.getSize(first).height,
            inInclusiveRange(RecentCallTokens.rowMinHeight, 90));
        expect(tester.getSize(_key('recent-call-delete-room:audio')),
            const Size(48, 48));
        expect(_key('recent-call-profile-room:audio'), findsOneWidget);
        expect(
            tester
                .widgetList<Divider>(find.byType(Divider))
                .every((divider) => divider.indent == 122),
            isTrue);
        await _capture(tester, dark ? 'dark-editing' : 'light-editing');
        await tester.tap(_key('recent-calls-tab-missed'));
        await tester.pumpAndSettle();
        expect(find.text('删除未接'), findsOneWidget);
        expect(find.text('小林'), findsOneWidget);
        expect(find.text('阿明'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        cache.onDelete();
      }
    });
  }

  testWidgets('info opens profile while the row calls back, including editing',
      (tester) async {
    var profiles = 0, calls = 0, deletes = 0;
    Widget row(bool editing) => Scaffold(
        body: RecentCallTile(
            record: callFixture(),
            editing: editing,
            enabled: true,
            onProfile: () => profiles++,
            onRedial: () => calls++,
            onDelete: () => deletes++));
    await mountRecentCalls(tester, row(false));
    await tester.pumpAndSettle();
    await tester.tap(_key('recent-call-profile-room:room-1'));
    expect(profiles, 1);
    expect(calls, 0);
    await tester.tap(find.textContaining('已接通'));
    expect(calls, 1);
    await mountRecentCalls(tester, row(true));
    await tester.pumpAndSettle();
    await tester.tap(_key('recent-call-profile-room:room-1'));
    await tester.tap(find.textContaining('已接通'));
    expect(profiles, 2);
    expect(calls, 1);
    await tester.tap(_key('recent-call-delete-room:room-1'));
    expect(deletes, 1);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(812, 375)]) {
    testWidgets('reference controls fit $size with 3x text and reduced motion',
        (tester) async {
      final box = RecentCallMemoryBox()
        ..backingMap['account-a'] = [
          callFixture(nickname: '一位名字特别长并且需要完整操作的联系人')
        ];
      final cache = CacheController(
          accountIDProvider: () => 'account-a', boxOpener: () async => box);
      try {
        await mountRecentCalls(tester, RecentCallsPage(cacheController: cache),
            size: size, textScale: 3);
        await tester.pumpAndSettle();
        await tester.tap(_key('recent-calls-edit'));
        await tester.pumpAndSettle();
        expect(find.text('完成').hitTestable(), findsOneWidget);
        expect(_key('recent-call-profile-room:room-1').hitTestable(),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        cache.onDelete();
      }
    });
  }
}
