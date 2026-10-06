import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/host/wallet_qr_scanner.dart';
import 'package:openim/widgets/qr_scanner/qr_gallery_service.dart';
import 'package:openim_common/openim_common.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../support/contacts/native_qr_scanner.dart';

const walletScannerAddress = 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8';

Finder walletScannerAction(String action) =>
    find.byKey(ValueKey('wallet-qr-$action'));

Future<void> initializeWalletScannerTests() async {
  SharedPreferences.setMockInitialValues({});
  await SpUtil().init();
  await NavigationGlassController.instance
      .setMode(NavigationGlassMode.translucent);
}

/// Replaces only album I/O. The real shared decode flow remains in the widget.
class WalletScannerGallery extends QrGalleryService {
  WalletScannerGallery({Future<String?> Function()? pick, this.read})
      : pick = pick ?? (() async => null);

  final Future<String?> Function() pick;
  final Future<String?> Function(String)? read;
  int pickCalls = 0;
  final paths = <String>[];

  @override
  Future<String?> pickImage() {
    pickCalls++;
    return pick();
  }

  @override
  Future<String?> readCode(String path) {
    paths.add(path);
    return read?.call(path) ?? Future<String?>.value();
  }
}

/// Uses the production wallet wrapper and the existing native camera harness.
class WalletScannerHost {
  WalletScannerHost(this.tester, {QrGalleryService? gallery, this.onMyQr})
      : native = NativeQrScanner(tester),
        gallery = gallery ?? WalletScannerGallery() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  }

  final WidgetTester tester;
  final NativeQrScanner native;
  final QrGalleryService gallery;
  final Future<void> Function()? onMyQr;
  final navigator = GlobalKey<NavigatorState>();
  final previewKey = GlobalKey();
  final results = <String?>[];
  int myQrCalls = 0;

  Future<void> mount({
    bool dark = false,
    bool granted = true,
    Size size = const Size(390, 844),
    double textScale = 1,
    String? previewFont,
    Locale locale = const Locale('zh', 'CN'),
    EdgeInsets padding = const EdgeInsets.only(top: 24, bottom: 20),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(RepaintBoundary(
      key: previewKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigator,
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
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          fontFamily: previewFont,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: padding,
            viewPadding: padding,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Builder(
            builder: (context) => Scaffold(
                  body: Column(children: [
                    const Text('Home'),
                    TextButton(
                      onPressed: () async {
                        results.add(await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                              builder: (_) => WalletQrScannerPage(
                                    gallery: gallery,
                                    onMyQrTap: () async {
                                      myQrCalls++;
                                      if (onMyQr != null) return onMyQr!();
                                      await navigator.currentState!.push<void>(
                                        MaterialPageRoute(
                                            builder: (_) => const Scaffold(
                                                body: Text('My QR'))),
                                      );
                                    },
                                  )),
                        ));
                      },
                      child: const Text('Open scanner'),
                    ),
                  ]),
                )),
      ),
    ));
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
    expect(find.byType(QRView), findsOneWidget);
    expect(native.channel, isNotNull);
    await native.permission(granted);
    await tester.pumpAndSettle();
  }

  void cover() {
    unawaited(navigator.currentState!.push<void>(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('Covered page')),
    )));
  }

  Future<void> close() async {
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      native.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  }
}
