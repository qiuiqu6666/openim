import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/home/wallet_home_view.dart';
import 'package:openim/pages/wallet/wallet_tab_shell.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final (width, scale, locale) in [
      (390.0, 1.0, const Locale('zh', 'CN')),
      (320.0, 3.0, const Locale('ja', 'JP')),
    ]) {
      testWidgets(
          'wallet main tab keeps a readable title and consumes bottom inset once in $brightness, $width px, $scale x, $locale',
          (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final active = ValueNotifier(3);
        addTearDown(active.dispose);
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
            locale: locale,
            supportedLocales: const [Locale('zh', 'CN'), Locale('ja', 'JP')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 44, bottom: 80),
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: WalletTabShell(
                activeTabIndexListenable: active,
                repository: const UnavailableWalletRepository()),
          ),
        ));
        await tester.pumpAndSettle();
        final title = find.byKey(const ValueKey('wallet-title-text'));
        expect(title, findsOneWidget);
        expect(tester.widget<Text>(title).data,
            locale.languageCode == 'ja' ? 'ウォレット' : '钱包');
        expect(tester.getRect(title).right, lessThanOrEqualTo(width));
        final view = tester.widget<WalletHomeView>(find.byType(WalletHomeView));
        expect(view.embeddedInMainTab, isTrue);
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.toolbarHeight ?? kToolbarHeight, kToolbarHeight);
        final home = find.byType(WalletHomeView);
        expect(tester.getRect(home).bottom, 844 - 80);
        expect(
            tester
                .getRect(find.byKey(const PageStorageKey('wallet-home-scroll')))
                .bottom,
            844 - 80);
        expect(
            MediaQuery.paddingOf(tester.element(find.byType(WalletHomeView)))
                .bottom,
            0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
