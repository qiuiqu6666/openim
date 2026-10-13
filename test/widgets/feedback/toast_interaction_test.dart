import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

const _longNotice = '''部分内容暂时无法加载，请检查网络连接后再次尝试。你可以继续查看已加载的消息，或稍后返回重新刷新列表。
如果刚才正在发送消息，请先查看消息旁的发送状态，避免重复发送。尚未提交的输入内容可以保留，网络恢复后再继续操作。
群组设置未能保存时，请稍后重新打开设置页面，确认当前状态后重试。若问题持续出现，可以通过设置中的帮助与反馈联系我们，并说明当时正在进行的操作。
请确认设备已经连接到可用的无线网络或移动网络，再尝试刷新会话列表。等待期间仍然可以阅读已有的聊天记录。''';

const _viewports = [
  (
    name: 'phone',
    size: Size(375, 812),
    scale: 1.0,
    safe: EdgeInsets.only(top: 24, bottom: 34),
    keyboard: EdgeInsets.zero,
  ),
  (
    name: '320px and 2x text',
    size: Size(320, 640),
    scale: 2.0,
    safe: EdgeInsets.only(top: 24, bottom: 34),
    keyboard: EdgeInsets.zero,
  ),
  (
    name: 'short landscape and 2x text',
    size: Size(640, 180),
    scale: 2.0,
    safe: EdgeInsets.fromLTRB(20, 10, 20, 10),
    keyboard: EdgeInsets.zero,
  ),
  (
    name: 'phone keyboard and 2x text',
    size: Size(375, 812),
    scale: 2.0,
    safe: EdgeInsets.only(top: 24, bottom: 34),
    keyboard: EdgeInsets.only(bottom: 400),
  ),
  (
    name: 'short landscape keyboard and 2x text',
    size: Size(640, 240),
    scale: 2.0,
    safe: EdgeInsets.fromLTRB(20, 10, 20, 10),
    keyboard: EdgeInsets.only(bottom: 130),
  ),
];

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'toast passes center and outside taps through all phases / $dark',
        (tester) async {
      var taps = 0;
      await _mount(
          tester,
          dark,
          GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand()));
      final shown = IMViews.showToast('所选消息包含无法转发的消息，请取消勾选后重试');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(187, 406));
      expect(taps, 1);
      await tester.pumpAndSettle();
      await shown;
      expect(find.text('所选消息包含无法转发的消息，请取消勾选后重试'), findsOneWidget);
      await tester.tapAt(const Offset(187, 406));
      await tester.tapAt(const Offset(20, 100));
      expect(taps, 3);
      expect(EasyLoading.isShow, isTrue);
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(187, 406));
      expect(taps, 4);
      await tester.pumpAndSettle();
      expect(EasyLoading.isShow, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('toast allows scrolling from the covered area / $dark',
        (tester) async {
      final scroll = ScrollController();
      await _mount(
          tester,
          dark,
          ListView.builder(
            controller: scroll,
            itemCount: 40,
            itemBuilder: (_, index) =>
                SizedBox(height: 80, child: Text('消息 $index')),
          ));
      final shown = IMViews.showToast('提示显示期间可以继续滑动');
      await tester.pumpAndSettle();
      await shown;
      await tester.dragFrom(const Offset(187, 406), const Offset(0, -200));
      await tester.pump();
      expect(scroll.offset, greaterThan(100));
      expect(EasyLoading.isShow, isTrue);
      await EasyLoading.dismiss(animation: false);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    });

    testWidgets('loading and progress remain modal after a toast / $dark',
        (tester) async {
      var taps = 0;
      await _mount(
          tester,
          dark,
          GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand()));
      var shown = IMViews.showToast('操作提示');
      await tester.pumpAndSettle();
      await shown;
      await tester.tapAt(const Offset(187, 406));
      expect(taps, 1);
      shown = EasyLoading.show(status: '正在处理');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      await shown;
      await tester.tapAt(const Offset(187, 406));
      await tester.tapAt(const Offset(20, 100));
      expect(taps, 1);
      shown = EasyLoading.showProgress(.5, status: '同步中');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      await shown;
      await tester.tapAt(const Offset(187, 406));
      await tester.tapAt(const Offset(20, 100));
      expect(taps, 1);
      await EasyLoading.dismiss(animation: false);
      await tester.pump();
      await tester.tapAt(const Offset(187, 406));
      expect(taps, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'replacement toast keeps its duration and remains non-modal / $dark',
        (tester) async {
      var taps = 0;
      await _mount(
          tester,
          dark,
          GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand()));
      var shown =
          IMViews.showToast('第一条', duration: const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await shown;
      await tester.pump(const Duration(milliseconds: 500));
      shown = IMViews.showToast('第二条', duration: const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await shown;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('第一条'), findsNothing);
      expect(find.text('第二条'), findsOneWidget);
      await tester.tapAt(const Offset(187, 406));
      expect(taps, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(EasyLoading.isShow, isFalse);
    });

    for (final viewport in _viewports) {
      testWidgets(
          'long notice fits ${viewport.name}, passes taps and expires / $dark',
          (tester) async {
        var taps = 0;
        await _mount(
          tester,
          dark,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
          size: viewport.size,
          textScale: viewport.scale,
          safe: viewport.safe,
          keyboard: viewport.keyboard,
        );
        final shown = IMViews.showToast(_longNotice);
        await tester.pumpAndSettle();
        await shown;
        _expectBoundedStack(
            tester, viewport.size, viewport.safe, viewport.keyboard);
        await tester.tapAt(tester.getCenter(find.text(_longNotice)));
        await tester.tapAt(const Offset(2, 2));
        expect(taps, 2);
        expect(EasyLoading.isShow, isTrue);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(EasyLoading.isShow, isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('long notice still permits scrolling with keyboard / $dark',
        (tester) async {
      final scroll = ScrollController();
      await _mount(
        tester,
        dark,
        ListView.builder(
          controller: scroll,
          itemCount: 40,
          itemBuilder: (_, index) =>
              SizedBox(height: 80, child: Text('消息 $index')),
        ),
        textScale: 2,
        safe: const EdgeInsets.only(top: 24, bottom: 34),
        keyboard: const EdgeInsets.only(bottom: 400),
      );
      final shown = IMViews.showToast(_longNotice);
      await tester.pumpAndSettle();
      await shown;
      await tester.dragFrom(
          tester.getCenter(find.text(_longNotice)), const Offset(0, -120));
      await tester.pump();
      expect(scroll.offset, greaterThan(50));
      expect(EasyLoading.isShow, isTrue);
      expect(tester.takeException(), isNull);
      await EasyLoading.dismiss(animation: false);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    });

    testWidgets('long notice replacement retains new duration / $dark',
        (tester) async {
      await _mount(tester, dark, const SizedBox.expand(),
          size: const Size(320, 640), textScale: 2);
      var shown =
          IMViews.showToast(_longNotice, duration: const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await shown;
      await tester.pump(const Duration(milliseconds: 500));
      shown = IMViews.showToast('已保存', duration: const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await shown;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(_longNotice), findsNothing);
      expect(find.text('已保存'), findsOneWidget);
      expect(EasyLoading.isShow, isTrue);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(EasyLoading.isShow, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'bounded long loading and progress keep full modal mask / $dark',
        (tester) async {
      var taps = 0;
      const size = Size(640, 240);
      const safe = EdgeInsets.fromLTRB(20, 10, 20, 10);
      const keyboard = EdgeInsets.only(bottom: 130);
      await _mount(
        tester,
        dark,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox.expand(),
        ),
        size: size,
        textScale: 2,
        safe: safe,
        keyboard: keyboard,
      );
      var shown = EasyLoading.show(
          status: _longNotice,
          indicator:
              const SizedBox.square(dimension: 50, child: Icon(Icons.sync)));
      await tester.pumpAndSettle();
      await shown;
      _expectBoundedStack(tester, size, safe, keyboard);
      await tester.tapAt(tester.getCenter(find.text(_longNotice)));
      await tester.tapAt(const Offset(2, 2));
      await tester.tapAt(const Offset(638, 238));
      expect(taps, 0);
      shown = EasyLoading.showProgress(.5, status: _longNotice);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      await shown;
      _expectBoundedStack(tester, size, safe, keyboard);
      await tester.tapAt(tester.getCenter(find.text(_longNotice)));
      await tester.tapAt(const Offset(2, 2));
      await tester.tapAt(const Offset(638, 238));
      expect(taps, 0);
      await EasyLoading.dismiss(animation: false);
      await tester.pump();
      await tester.tapAt(const Offset(638, 238));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('short phone toast retains original geometry / $dark',
        (tester) async {
      await _mount(tester, dark, const SizedBox.expand());
      var shown = IMViews.showToast('已保存');
      await tester.pumpAndSettle();
      await shown;
      final bounded = tester.getRect(find.text('已保存'));
      await EasyLoading.dismiss(animation: false);
      await tester.pump();
      EasyLoading.instance.customAnimation = _OriginalOpacityAnimation();
      shown = IMViews.showToast('已保存');
      await tester.pumpAndSettle();
      await shown;
      final original = tester.getRect(find.text('已保存'));
      expect(bounded.left, closeTo(original.left, .01));
      expect(bounded.top, closeTo(original.top, .01));
      expect(bounded.width, closeTo(original.width, .01));
      expect(bounded.height, closeTo(original.height, .01));
      expect(tester.takeException(), isNull);
      // Widget-test timer invariants run before the registered tearDown.
      // The reference toast is still visible after the geometry comparison.
      await EasyLoading.dismiss(animation: false);
      await tester.pump();
      expect(EasyLoading.isShow, isFalse);
    });
  }
}

void _expectBoundedStack(
    WidgetTester tester, Size size, EdgeInsets safe, EdgeInsets keyboard) {
  final finder = find.text(_longNotice);
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.maxLines, 3);
  expect(paragraph.overflow, TextOverflow.ellipsis);
  expect(paragraph.didExceedMaxLines, isTrue);
  final content = tester
      .widget<FittedBox>(find.byKey(const ValueKey('global-feedback-content')));
  expect(content.fit, BoxFit.scaleDown);
  final bounds = tester.getRect(finder);
  expect(
      bounds.left,
      greaterThanOrEqualTo(
          (safe.left > keyboard.left ? safe.left : keyboard.left) - .01));
  expect(
      bounds.top,
      greaterThanOrEqualTo(
          (safe.top > keyboard.top ? safe.top : keyboard.top) - .01));
  expect(
      bounds.right,
      lessThanOrEqualTo(size.width -
          (safe.right > keyboard.right ? safe.right : keyboard.right) +
          .01));
  expect(
      bounds.bottom,
      lessThanOrEqualTo(size.height -
          (safe.bottom > keyboard.bottom ? safe.bottom : keyboard.bottom) +
          .01));
  expect(tester.takeException(), isNull);
}

class _OriginalOpacityAnimation extends EasyLoadingAnimation {
  @override
  Widget buildWidget(Widget child, AnimationController controller,
          AlignmentGeometry alignment) =>
      IgnorePointer(child: Opacity(opacity: controller.value, child: child));
}

Future<void> _mount(WidgetTester tester, bool dark, Widget body,
    {Size size = const Size(375, 812),
    double textScale = 1,
    EdgeInsets safe = EdgeInsets.zero,
    EdgeInsets keyboard = EdgeInsets.zero}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final loading = EasyLoading.instance;
  final interactions = loading.userInteractions;
  final mask = loading.maskType;
  final animation = loading.animationStyle;
  final customAnimation = loading.customAnimation;
  configureEasyLoadingInteractions();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    builder: EasyLoading.init(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewPadding: safe,
          viewInsets: keyboard,
        ),
        child: child!,
      ),
    ),
    home: Scaffold(resizeToAvoidBottomInset: false, body: body),
  ));
  addTearDown(() async {
    await EasyLoading.dismiss(animation: false);
    await tester.pumpWidget(const SizedBox());
    loading
      ..userInteractions = interactions
      ..maskType = mask
      ..animationStyle = animation
      ..customAnimation = customAnimation;
  });
  await tester.pump();
}
