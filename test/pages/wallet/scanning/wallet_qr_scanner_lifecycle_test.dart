import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import 'support/wallet_scanner_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeWalletScannerTests);

  testWidgets(
      'covered wallet scanner ignores camera and resumes when uncovered',
      (tester) async {
    final h = WalletScannerHost(tester);
    try {
      await h.mount();
      final scanner = tester.element(find.byType(QRView));
      h.native.cameraCalls.clear();
      h.cover();
      await tester.pumpAndSettle();
      expect(h.native.cameraCalls, contains('pauseCamera'));
      expect(h.native.cameraCalls, isNot(contains('resumeCamera')));
      await h.native.recognize(walletScannerAddress);
      await tester.pump();
      expect(h.results, isEmpty);
      expect(find.text('Covered page'), findsOneWidget);
      h.native.cameraCalls.clear();
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(QRView)), same(scanner));
      expect(h.native.cameraCalls, contains('resumeCamera'));
      await h.native.recognize(walletScannerAddress);
      await tester.pumpAndSettle();
      expect(h.results, [walletScannerAddress]);
    } finally {
      await h.close();
    }
  });

  testWidgets('foreground cannot resume a covered or dismissed camera',
      (tester) async {
    final h = WalletScannerHost(tester);
    try {
      await h.mount();
      h.cover();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      h.native.cameraCalls.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.native.cameraCalls, isNot(contains('resumeCamera')));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      h.native.cameraCalls.clear();
      h.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await h.native.recognize(walletScannerAddress);
      await tester.pump();
      expect(h.results, isEmpty);
      expect(h.native.cameraCalls, isNot(contains('resumeCamera')));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.native.cameraCalls, contains('resumeCamera'));
      await h.native.recognize(walletScannerAddress);
      await tester.pumpAndSettle();
      expect(h.results, [walletScannerAddress]);
    } finally {
      await h.close();
    }
  });

  testWidgets(
      'native result during dismissal and late creation cannot pop twice',
      (tester) async {
    final h = WalletScannerHost(tester);
    try {
      await h.mount();
      final lateCreated = tester
          .widget<AndroidView>(find.byType(AndroidView))
          .onPlatformViewCreated!;
      h.navigator.currentState!.pop();
      await h.native.recognize(walletScannerAddress);
      await tester.pumpAndSettle();
      expect(h.results, [null]);
      expect(find.text('Home'), findsOneWidget);
      final commands = h.native.cameraCalls.length;
      lateCreated(9999);
      await tester.pump();
      expect(h.native.cameraCalls, hasLength(commands));
      expect(h.results, [null]);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close();
    }
  });

  testWidgets('late album decode after scanner closes cannot navigate',
      (tester) async {
    final decoded = Completer<String?>();
    final gallery = WalletScannerGallery(
        pick: () async => '/fixture.png', read: (_) => decoded.future);
    final h = WalletScannerHost(tester, gallery: gallery);
    try {
      await h.mount();
      await tester.tap(walletScannerAction('album'));
      await tester.pump();
      expect(gallery.paths, ['/fixture.png']);
      await tester.tap(walletScannerAction('back'));
      await tester.pumpAndSettle();
      expect(h.results, [null]);
      decoded.complete(walletScannerAddress);
      await tester.pumpAndSettle();
      expect(h.results, [null]);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      if (!decoded.isCompleted) decoded.complete(null);
      await h.close();
    }
  });

  for (final closeWhileWaiting in [false, true]) {
    testWidgets(
        'album waits for foreground; close while waiting=$closeWhileWaiting',
        (tester) async {
      final pick = Completer<String?>();
      final decoded = Completer<String?>();
      final gallery = WalletScannerGallery(
          pick: () => pick.future, read: (_) => decoded.future);
      final h = WalletScannerHost(tester, gallery: gallery);
      try {
        await h.mount();
        await tester.tap(walletScannerAction('album'));
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        pick.complete('/fixture.png');
        await tester.pump();
        expect(gallery.paths, isEmpty);
        expect(h.results, isEmpty);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        await tester.pump();
        expect(gallery.paths, ['/fixture.png']);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        decoded.complete(walletScannerAddress);
        await tester.pump();
        expect(h.results, isEmpty);
        if (closeWhileWaiting) {
          await tester.tap(walletScannerAction('back'));
          await tester.pumpAndSettle();
          expect(h.results, [null]);
        }
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(h.results, closeWhileWaiting ? [null] : [walletScannerAddress]);
        expect(find.text('Home'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        if (!pick.isCompleted) pick.complete(null);
        if (!decoded.isCompleted) decoded.complete(null);
        await h.close();
      }
    });
  }
}
