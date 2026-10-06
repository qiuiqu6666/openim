import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/wallet_receive_screen.dart';
import 'package:openim/pages/wallet/wallet_share_service.dart';
import 'package:openim/pages/wallet/widgets/wallet_99chat_tokens.dart';
import 'package:openim_common/openim_common.dart'
    show Styles, configureEasyLoadingInteractions;

import '../../data/wallet_fund_test_api.dart';

export '../../data/wallet_fund_test_api.dart';

class DepositTestShareService extends WalletShareService {
  final List<String> copies = [];
  final List<String> shares = [];
  final List<String> messages = [];
  final List<GlobalKey> saves = [];
  final List<GlobalKey> imageShares = [];
  final List<Color> saveBackgrounds = [];
  final List<Color> imageShareBackgrounds = [];
  WalletCopyResult copyResult = WalletCopyResult.success;
  WalletSaveImgResult saveResult = WalletSaveImgResult.success;
  WalletSystemShareResult shareResult = WalletSystemShareResult.success;
  Future<WalletSaveImgResult> Function(BuildContext context, GlobalKey key)?
      saveResponse;
  Future<WalletSystemShareResult> Function(BuildContext context, GlobalKey key)?
      shareResponse;
  @override
  Future<WalletCopyResult> copyAddr(String addr) async {
    copies.add(addr);
    return copyResult;
  }

  @override
  Future<WalletSystemShareResult> shareSystemText(String text) async {
    shares.add(text);
    return shareResult;
  }

  @override
  Future<WalletSystemShareResult> shareSystemImage(
      BuildContext context, GlobalKey key,
      {required bool Function() isCurrent,
      Color backgroundColor = const Color(0xFFFFFFFF)}) {
    if (!isCurrent()) return Future.value(WalletSystemShareResult.dismissed);
    imageShares.add(key);
    imageShareBackgrounds.add(backgroundColor);
    return shareResponse?.call(context, key) ?? Future.value(shareResult);
  }

  @override
  Future<WalletSaveImgResult> saveQrImg(BuildContext context, GlobalKey key,
      {bool Function()? isCurrent,
      Color backgroundColor = const Color(0xFFFFFFFF)}) {
    if (isCurrent?.call() == false) {
      return Future.value(WalletSaveImgResult.unknown);
    }
    saves.add(key);
    saveBackgrounds.add(backgroundColor);
    return saveResponse?.call(context, key) ?? Future.value(saveResult);
  }

  @override
  Future<WalletLaunchAppResult> launchSms(String addr) async {
    messages.add(addr);
    return WalletLaunchAppResult.success;
  }
}

Finder depositKey(String key) => find.byKey(ValueKey(key));

Future<void> pumpWalletDeposit(
  WidgetTester tester, {
  required WalletTestFundApi api,
  String Function()? accountProvider,
  DepositTestShareService? share,
  FundCurrency currency = FundCurrency.usdt,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh', 'CN'),
  Size size = const Size(390, 844),
  double textScale = 1,
  GlobalKey? boundaryKey,
  GlobalKey? appBoundaryKey,
  String? fontFamily,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final previousLocale = Get.locale;
  final previousDark = Styles.isDark;
  Get.locale = locale;
  addTearDown(() {
    Get.locale = previousLocale;
    Styles.isDark = previousDark;
  });
  final dark = brightness == Brightness.dark;
  Styles.isDark = dark;
  configureEasyLoadingInteractions();
  EasyLoading.instance.toastPosition = EasyLoadingToastPosition.center;
  addTearDown(() => EasyLoading.dismiss(animation: false));
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
            locale: locale,
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('zh', 'TW'),
              Locale('en'),
              Locale('ja'),
              Locale('ko'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            theme: ThemeData(
                brightness: brightness,
                fontFamily: fontFamily,
                colorScheme: ColorScheme.fromSeed(
                    seedColor: AppTokens.accent,
                    brightness: brightness,
                    surface: AppTokens.appSurface(dark))),
            builder: EasyLoading.init(
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(textScale)),
                    child:
                        RepaintBoundary(key: appBoundaryKey, child: child!))),
            home: RepaintBoundary(
                key: boundaryKey,
                child: WalletReceiveScreen(
                    addr: 'legacy-address-must-not-be-used',
                    api: api,
                    accountProvider:
                        accountProvider ?? () => 'server:test-user',
                    shareService: share ?? DepositTestShareService(),
                    currency: currency)),
          )));
  await tester.pump();
  await tester.pump();
}
