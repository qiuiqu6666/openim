// Motion regressions: repaired interactions must remain stable.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/wallet_controller.dart';
import 'package:openim/pages/wallet/host/wallet_navigation.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';
import 'package:openim/widgets/register_page_bg.dart';
import 'package:openim_common/openim_common.dart';

import '../../pages/wallet/home/wallet_home_test_support.dart';

String? _fontFamily;

void main() {
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (!font.existsSync()) return;
    await (FontLoader('WalletMotionAuditCjk')
          ..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes()))))
        .load();
    _fontFamily = 'WalletMotionAuditCjk';
  });
  testWidgets('slight initial edge movement preserves vertical list scrolling',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    const pageKey = ValueKey('wallet-route-audit-page');
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('base')),
    ));
    unawaited(navigator.currentState!.push(AppMaterialPageRoute<void>(
      builder: (_) => Scaffold(
        key: pageKey,
        body: ListView(
          controller: scroll,
          children: [
            for (var i = 0; i < 50; i++)
              SizedBox(height: 60, child: Text('row $i'))
          ],
        ),
      ),
    )));
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byKey(pageKey));
    final gesture = await tester.startGesture(const Offset(10, 400));
    await gesture.moveBy(const Offset(2, -1));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(20, -80),
        timeStamp: const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -40),
        timeStamp: const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 16));
    final during = tester.getRect(find.byKey(pageKey));
    expect(during.left, before.left);
    expect(scroll.offset, greaterThan(0));
    debugPrint('MOTION wallet route diagonal: page dx='
        '${during.left - before.left}, list offset=${scroll.offset}');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(pageKey)), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final brightness in Brightness.values) {
    testWidgets(
        'audit long balance arriving moves wallet actions ($brightness)',
        (tester) async {
      final previousDark = Styles.isDark;
      addTearDown(() => Styles.isDark = previousDark);
      final pending = Completer<WalletDto>();
      final repository = HomeTestRepository()..respond = () => pending.future;
      final controller = WalletController(repo: repository);
      addTearDown(controller.dispose);
      final load = controller.load();
      await pumpWalletHome(tester,
          controller: controller,
          size: const Size(320, 812),
          fontFamily: _fontFamily,
          brightness: brightness);
      final before = tester.getRect(walletHomeKey('wallet-action-receive'));
      final amountBefore = tester.getRect(walletHomeKey('wallet-total-amount'));
      pending.complete(walletHomeLongFixture);
      await load;
      await tester.pump(const Duration(milliseconds: 16));
      final after = tester.getRect(walletHomeKey('wallet-action-receive'));
      final amountAfter = tester.getRect(walletHomeKey('wallet-total-amount'));
      expect(after.top, closeTo(before.top, .01));
      expect(amountAfter.height, closeTo(amountBefore.height, .01));
      debugPrint('MOTION wallet long balance $brightness: actions dy='
          '${after.top - before.top}, amount dh='
          '${amountAfter.height - amountBefore.height}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('failed refresh keeps the retained wallet stable ($brightness)',
        (tester) async {
      final previousDark = Styles.isDark;
      addTearDown(() => Styles.isDark = previousDark);
      final repository = HomeTestRepository();
      final controller = await loadedHomeController(repository: repository);
      await pumpWalletHome(tester,
          controller: controller,
          fontFamily: _fontFamily,
          brightness: brightness);
      final before = tester.getRect(walletHomeKey('wallet-total-amount'));
      repository.respond =
          () => Future.error(const WalletBackendUnavailableException());
      await controller.load(force: true);
      await tester.pump(const Duration(milliseconds: 16));
      final after = tester.getRect(walletHomeKey('wallet-total-amount'));
      expect(controller.totalBal, walletHomeFixture.totalBal);
      expect(after.top, before.top);
      debugPrint('MOTION wallet refresh failure $brightness: total dy='
          '${after.top - before.top}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'auth wrapper viewport stays above the keyboard '
        'while keyboard is open ($brightness)', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousDark = Styles.isDark;
      Styles.isDark = brightness == Brightness.dark;
      addTearDown(() => Styles.isDark = previousDark);
      final media = ValueNotifier(const MediaQueryData(
        size: Size(375, 812),
        padding: EdgeInsets.only(top: 24, bottom: 24),
        viewPadding: EdgeInsets.only(top: 24, bottom: 24),
      ));
      addTearDown(media.dispose);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: ValueListenableBuilder<MediaQueryData>(
            valueListenable: media,
            builder: (_, value, __) => MediaQuery(
              data: value,
              child: const RegisterBgView(child: SizedBox(height: 1200)),
            ),
          ),
        ),
      ));
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      final before = tester.getRect(find.byType(SingleChildScrollView));
      final offsetBefore = scroll.position.pixels;
      media.value = media.value.copyWith(
        padding: const EdgeInsets.only(top: 24),
        viewInsets: const EdgeInsets.only(bottom: 300),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final after = tester.getRect(find.byType(SingleChildScrollView));
      expect(after.bottom, lessThanOrEqualTo(812 - 300));
      expect(after.height, lessThan(before.height));
      expect(scroll.position.pixels, closeTo(offsetBefore, .01));
      debugPrint('MOTION auth wrapper keyboard $brightness: viewport dh='
          '${after.height - before.height}, offset delta='
          '${scroll.position.pixels - offsetBefore}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
