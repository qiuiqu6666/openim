import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/widgets/qr_scanner/qr_scanner_labels.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import 'support/wallet_scanner_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeWalletScannerTests);

  for (final code in [walletScannerAddress, 'https://example.test/plain-qr']) {
    testWidgets('camera returns trimmed raw text once: $code', (tester) async {
      final h = WalletScannerHost(tester);
      try {
        await h.mount();
        await h.native.recognize('   ');
        await tester.pump();
        expect(h.results, isEmpty);
        await Future.wait([
          h.native.recognize('  $code\n'),
          h.native.recognize('  $code\n'),
        ]);
        await tester.pumpAndSettle();
        expect(h.results, [code]);
        expect(find.text('Home'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close();
      }
    });
  }

  for (final code in [walletScannerAddress, 'plain wallet QR text']) {
    testWidgets('album returns trimmed raw text: $code', (tester) async {
      final gallery = WalletScannerGallery(
          pick: () async => '/fixture.png', read: (_) async => '\n$code  ');
      final h = WalletScannerHost(tester, gallery: gallery);
      try {
        await h.mount();
        await tester.tap(walletScannerAction('album'));
        await tester.pumpAndSettle();
        expect(h.results, [code]);
        expect(gallery.paths, ['/fixture.png']);
        expect(tester.takeException(), isNull);
      } finally {
        await h.close();
      }
    });
  }

  for (final (locale, message) in const [
    (Locale('zh', 'CN'), '未识别到有效的二维码'),
    (Locale('zh', 'TW'), '未識別到有效的二維碼'),
    (Locale('en'), 'No valid QR code found'),
    (Locale('ja'), '有効なQRコードが見つかりません'),
    (Locale('ko'), '유효한 QR 코드를 찾지 못했습니다'),
  ]) {
    for (final code in [null, ' \n ']) {
      testWidgets('empty/unrecognized album warns in $locale: $code',
          (tester) async {
        final gallery = WalletScannerGallery(
            pick: () async => '/fixture.png', read: (_) async => code);
        final h = WalletScannerHost(tester, gallery: gallery);
        try {
          await h.mount(locale: locale);
          h.native.cameraCalls.clear();
          await tester.tap(walletScannerAction('album'));
          await tester.pumpAndSettle();
          expect(h.results, isEmpty);
          expect(find.text(message), findsOneWidget);
          expect(h.native.cameraCalls, contains('resumeCamera'));
          await h.native.recognize(walletScannerAddress);
          await tester.pumpAndSettle();
          expect(h.results, [walletScannerAddress]);
        } finally {
          await h.close();
        }
      });
    }
  }

  testWidgets('camera cannot override a chosen image while decoding is pending',
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
      await h.native.recognize(walletScannerAddress);
      await tester.pump();
      expect(h.results, isEmpty);
      decoded.complete(' selected album QR ');
      await tester.pumpAndSettle();
      expect(h.results, ['selected album QR']);
    } finally {
      if (!decoded.isCompleted) decoded.complete(null);
      await h.close();
    }
  });

  testWidgets('cancelled album restores camera and ignores competing callbacks',
      (tester) async {
    final pick = Completer<String?>();
    final gallery = WalletScannerGallery(pick: () => pick.future);
    final h = WalletScannerHost(tester, gallery: gallery);
    try {
      await h.mount();
      h.native.cameraCalls.clear();
      await tester.tap(walletScannerAction('album'));
      await tester.pump();
      expect(h.native.cameraCalls, contains('pauseCamera'));
      await h.native.recognize(walletScannerAddress);
      await tester.tap(walletScannerAction('album'), warnIfMissed: false);
      await tester.pump();
      expect(h.results, isEmpty);
      expect(gallery.pickCalls, 1);
      h.native.cameraCalls.clear();
      pick.complete(null);
      await tester.pumpAndSettle();
      expect(gallery.paths, isEmpty);
      expect(h.native.cameraCalls, contains('resumeCamera'));
      await h.native.recognize(walletScannerAddress);
      await tester.pumpAndSettle();
      expect(h.results, [walletScannerAddress]);
    } finally {
      if (!pick.isCompleted) pick.complete(null);
      await h.close();
    }
  });

  testWidgets('camera permission denial leaves album recognition usable',
      (tester) async {
    final gallery = WalletScannerGallery(
        pick: () async => '/fixture.png',
        read: (_) async => walletScannerAddress);
    final h = WalletScannerHost(tester, gallery: gallery);
    try {
      await h.mount(granted: false);
      await tester.tap(walletScannerAction('flash'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.native.calls, isNot(contains('toggleFlash')));
      await tester.tap(walletScannerAction('album'));
      await tester.pumpAndSettle();
      expect(h.results, [walletScannerAddress]);
      expect(gallery.pickCalls, 1);
    } finally {
      await h.close();
    }
  });

  testWidgets('failed album read resumes camera and a later image can succeed',
      (tester) async {
    var fail = true;
    final gallery = WalletScannerGallery(
      pick: () async => '/fixture.png',
      read: (_) async {
        if (fail) throw PlatformException(code: 'fixture-decode-error');
        return walletScannerAddress;
      },
    );
    final h = WalletScannerHost(tester, gallery: gallery);
    try {
      await h.mount();
      h.native.cameraCalls.clear();
      await tester.tap(walletScannerAction('album'));
      await tester.pumpAndSettle();
      expect(h.results, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(h.native.cameraCalls, contains('resumeCamera'));
      fail = false;
      await tester.tap(walletScannerAction('album'));
      await tester.pumpAndSettle();
      expect(h.results, [walletScannerAddress]);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close();
    }
  });

  testWidgets(
      'flash uses native permission and recovers after a toggle failure',
      (tester) async {
    final h = WalletScannerHost(tester);
    try {
      await h.mount(granted: false);
      await tester.tap(walletScannerAction('flash'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.native.calls, isNot(contains('toggleFlash')));
      await h.native.permission(true);
      await tester.pumpAndSettle();
      h.native.flashFailure = PlatformException(code: 'fixture-flash-error');
      await tester.tap(walletScannerAction('flash'));
      await tester.pumpAndSettle();
      expect(h.native.flashOn, isFalse);
      h.native.flashFailure = null;
      await tester.tap(walletScannerAction('flash'));
      await tester.pumpAndSettle();
      expect(h.native.flashOn, isTrue);
      await tester.tap(walletScannerAction('flash'));
      await tester.pumpAndSettle();
      expect(h.native.flashOn, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close();
    }
  });

  testWidgets('no-flash hardware sends no flash command but still scans',
      (tester) async {
    final h = WalletScannerHost(tester)..native.hasFlash = false;
    try {
      await h.mount();
      await tester.tap(walletScannerAction('flash'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.native.calls, isNot(contains('toggleFlash')));
      await h.native.recognize(walletScannerAddress);
      await tester.pumpAndSettle();
      expect(h.results, [walletScannerAddress]);
    } finally {
      await h.close();
    }
  });

  testWidgets('my QR suspends scanning and returns to the original camera',
      (tester) async {
    final h = WalletScannerHost(tester);
    try {
      await h.mount();
      final scanner = tester.element(find.byType(QRView));
      h.native.cameraCalls.clear();
      await tester.tap(walletScannerAction('my-code'));
      await tester.pumpAndSettle();
      expect(find.text('My QR'), findsOneWidget);
      expect(h.native.cameraCalls, contains('pauseCamera'));
      await h.native.recognize(walletScannerAddress);
      await tester.pump();
      expect(h.results, isEmpty);
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

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
  ]) {
    testWidgets('header title and album never overlap at 320px 2x in $locale',
        (tester) async {
      final h = WalletScannerHost(tester);
      try {
        await h.mount(locale: locale, size: const Size(320, 568), textScale: 2);
        final labels = QrScannerLabels(locale);
        final title = tester.getRect(find.text(labels.title));
        final album = tester.getRect(walletScannerAction('album'));
        final back = tester.getRect(walletScannerAction('back'));
        expect(title.overlaps(album), isFalse,
            reason: 'Title $title and album $album must not overlap');
        expect(title.overlaps(back), isFalse,
            reason: 'Title $title and back $back must not overlap');
        final frame = tester.getRect(walletScannerAction('frame'));
        final instruction = tester.getRect(walletScannerAction('instruction'));
        final flash = tester.getRect(walletScannerAction('flash'));
        final myCode = tester.getRect(walletScannerAction('my-code'));
        expect(frame.overlaps(instruction), isFalse,
            reason: 'Frame $frame and instruction $instruction must be clear');
        expect(frame.overlaps(flash), isFalse,
            reason: 'Frame $frame and flash $flash must not overlap');
        expect(frame.overlaps(myCode), isFalse,
            reason: 'Frame $frame and my QR $myCode must not overlap');
        final albumText = tester.getRect(find.text(labels.album));
        expect(albumText.left, greaterThanOrEqualTo(album.left));
        expect(albumText.right, lessThanOrEqualTo(album.right));
        expect(albumText.top, greaterThanOrEqualTo(album.top));
        expect(albumText.bottom, lessThanOrEqualTo(album.bottom));
        for (final text in [labels.title, labels.album]) {
          final paragraph =
              tester.renderObject<RenderParagraph>(find.text(text));
          expect(paragraph.didExceedMaxLines, isFalse,
              reason: 'The complete localized label must remain readable');
          for (final box in paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: text.length))) {
            expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.01));
            expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.01));
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        await h.close();
      }
    });
  }

  for (final dark in [false, true]) {
    for (final size in [
      const Size(390, 844),
      const Size(320, 568),
      const Size(568, 320),
    ]) {
      testWidgets('actual scanner actions fit $size ${dark ? 'dark' : 'light'}',
          (tester) async {
        final h = WalletScannerHost(tester);
        try {
          final insets = size.width > size.height
              ? const EdgeInsets.fromLTRB(44, 24, 16, 16)
              : const EdgeInsets.only(top: 24, bottom: 20);
          await h.mount(
              dark: dark,
              size: size,
              textScale: size.width == 390 ? 1 : 2,
              padding: insets);
          expect(tester.getRect(find.byType(QRView)),
              Rect.fromLTWH(0, 0, size.width, size.height));
          final safe = Rect.fromLTRB(insets.left, insets.top,
              size.width - insets.right, size.height - insets.bottom);
          for (final id in ['back', 'album', 'flash', 'my-code']) {
            final bounds = tester.getRect(walletScannerAction(id));
            expect(bounds.left, greaterThanOrEqualTo(safe.left));
            expect(bounds.top, greaterThanOrEqualTo(safe.top));
            expect(bounds.right, lessThanOrEqualTo(safe.right));
            expect(bounds.bottom, lessThanOrEqualTo(safe.bottom));
            expect(bounds.width, greaterThanOrEqualTo(48));
            expect(bounds.height, greaterThanOrEqualTo(48));
            expect(walletScannerAction(id).hitTestable(), findsOneWidget);
          }
          expect(walletScannerAction('frame'), findsOneWidget);
          final frame = tester.getRect(walletScannerAction('frame'));
          for (final id in ['flash', 'my-code']) {
            final action = tester.getRect(walletScannerAction(id));
            expect(frame.overlaps(action), isFalse,
                reason: 'Frame $frame and $id $action must not overlap');
          }
          expect(tester.takeException(), isNull);
          await tester.tap(walletScannerAction('back'));
          await tester.pumpAndSettle();
          expect(h.results, [null]);
        } finally {
          await h.close();
        }
      });
    }
  }
}
