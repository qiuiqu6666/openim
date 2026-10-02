import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/trade_password_page.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim_common/openim_common.dart';

class _PasswordService extends StubSettingsService {
  final submitted = <String>[];
  Completer<void>? pending;
  bool fail = false;
  Object? failure;

  @override
  bool get isBackendAvailable => true;

  @override
  Future<void> setTradePassword(String password) async {
    submitted.add(password);
    if (failure != null) throw failure!;
    if (fail) throw StateError('unavailable');
    await pending?.future;
  }
}

Widget _host(Widget child, {bool dark = false, double textScale = 1}) =>
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: EasyLoading.init(
          builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  padding: const EdgeInsets.only(top: 24, bottom: 34),
                ),
                child: child!,
              )),
      home: child,
    );

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _enter(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(ValueKey('trade-password-key-$digit')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'password layout and keypad fit in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      _screen(tester, const Size(375, 660));
      await tester.pumpWidget(_host(const TradePasswordPage(), dark: dark));
      await tester.pumpAndSettle();

      expect(find.text('用于支付、转账、红包等资金操作'), findsOneWidget);
      expect(find.text('资金安全保障中，请放心设置'), findsOneWidget);
      final gridTop = tester
          .getTopLeft(
            find.byKey(const ValueKey('trade-password-keypad')),
          )
          .dy;
      final contentBottom = tester
          .getBottomRight(
            find.byType(SingleChildScrollView),
          )
          .dy;
      for (var i = 0; i < 6; i++) {
        final cell = find.byKey(ValueKey('trade-password-cell-$i'));
        final bounds = tester.getRect(cell);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(375));
        expect(bounds.bottom, lessThan(gridTop));
        expect(bounds.bottom, lessThanOrEqualTo(contentBottom));
      }
      for (final digit in '0123456789'.split('')) {
        final key = find.byKey(ValueKey('trade-password-key-$digit'));
        expect(key.hitTestable(), findsOneWidget);
        expect(tester.getSize(key).height, greaterThanOrEqualTo(48));
      }
      final key = tester.widget<Material>(
        find.byKey(const ValueKey('trade-password-key-1')),
      );
      expect(key.color, AppTokens.surface(dark: dark));
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(320, 568), const Size(640, 360)]) {
    testWidgets('password keypad fits small or landscape screen $size',
        (tester) async {
      _screen(tester, size);
      await tester.pumpWidget(_host(const TradePasswordPage()));
      await tester.pumpAndSettle();
      expect(find.text('0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('large text keeps the keypad accessible', (tester) async {
    _screen(tester, const Size(320, 568));
    await tester.pumpWidget(_host(const TradePasswordPage(), textScale: 1.8));
    await tester.pumpAndSettle();
    expect(find.text('0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'delete, mismatch and confirmation submit only matching passwords',
      (tester) async {
    _screen(tester, const Size(375, 812));
    final service = _PasswordService();
    bool? result;
    await tester.pumpWidget(_host(Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => TradePasswordPage(service: service),
            ));
          },
          child: const Text('打开'),
        ),
      ),
    )));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await _enter(tester, '12');
    await tester.tap(find.byKey(const ValueKey('trade-password-key-del')));
    await _enter(tester, '23456');
    expect(find.text('请再次输入交易密码'), findsOneWidget);
    await _enter(tester, '654321');
    expect(find.text('两次输入的密码不一致，请重新确认'), findsOneWidget);
    expect(service.submitted, isEmpty);
    await _enter(tester, '123456');
    expect(service.submitted, ['123456']);
    expect(result, isTrue);
    expect(find.text('支付密码设置成功'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('confirmation can reset and a failed submission can be retried',
      (tester) async {
    _screen(tester, const Size(375, 812));
    final service = _PasswordService()..fail = true;
    await tester.pumpWidget(_host(TradePasswordPage(service: service)));
    await _enter(tester, '123456');
    await tester.tap(find.text('重新设置密码'));
    await tester.pumpAndSettle();
    expect(find.text('请输入交易密码'), findsOneWidget);
    await _enter(tester, '654321');
    await _enter(tester, '654321');
    expect(find.text('设置失败，请稍后重试'), findsOneWidget);
    expect(find.text('0').hitTestable(), findsOneWidget);
    expect(service.submitted, ['654321']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server failure is visible and preserves the confirmation flow',
      (tester) async {
    _screen(tester, const Size(375, 812));
    final service = _PasswordService()
      ..failure = (20036, 'FundPayPasswordLocked');
    await tester.pumpWidget(_host(TradePasswordPage(service: service)));
    await _enter(tester, '123456');
    await _enter(tester, '123456');
    expect(find.text('支付密码错误次数过多，请 15 分钟后重试'), findsOneWidget);
    expect(find.text('请再次输入交易密码'), findsOneWidget);
    expect(find.text('0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submitting disables all numeric actions', (tester) async {
    _screen(tester, const Size(375, 812));
    final service = _PasswordService()..pending = Completer<void>();
    await tester.pumpWidget(_host(TradePasswordPage(service: service)));
    await _enter(tester, '123456');
    await _enter(tester, '123456');
    expect(find.text('正在提交...'), findsOneWidget);
    await tester.tap(find.text('0'));
    await tester.tap(find.byKey(const ValueKey('trade-password-key-del')));
    await tester.pump();
    expect(service.submitted, ['123456']);
    final semantics = tester.widget<Semantics>(find
        .ancestor(
          of: find.byKey(const ValueKey('trade-password-key-0')),
          matching: find.byType(Semantics),
        )
        .first);
    expect(semantics.properties.enabled, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    service.pending!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
