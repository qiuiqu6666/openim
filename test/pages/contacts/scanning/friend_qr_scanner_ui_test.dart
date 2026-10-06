import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/scanning/friend_qr_gallery_service.dart';
import 'package:openim/pages/contacts/scanning/friend_qr_scanner.dart';
import 'package:openim_common/openim_common.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/contacts/native_qr_scanner.dart';

const _invite = 'openim://user/peer?source=qrcode&inviteCode=fi_test';
const _link = 'openim://user/album-peer?source=link&inviteCode=fi_album';
final _previewOutput = Platform.environment['FRIEND_QR_SCANNER_PREVIEW'] ?? '';
Finder _action(String id) => find.byKey(ValueKey('friend-qr-$id'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
  });

  for (final dark in [false, true]) {
    testWidgets(
        '${dark ? 'dark' : 'light'} scanner keeps preview and actions usable',
        (tester) async {
      final h = _ScannerHost(tester);
      try {
        await h.mount(dark: dark);
        expect(find.text('扫一扫'), findsWidgets);
        expect(find.textContaining('二维码'), findsWidgets);
        final preview = tester.getRect(find.byType(QRView));
        expect(preview, const Rect.fromLTWH(0, 0, 390, 844),
            reason: 'The camera fills the page behind the scanning controls');
        for (final id in ['back', 'album', 'flash', 'my-code']) {
          final bounds = tester.getRect(_action(id));
          expect(preview.contains(bounds.center), isTrue);
          expect(bounds.width, greaterThanOrEqualTo(44));
          expect(bounds.height, greaterThanOrEqualTo(44));
        }
        expect(tester.takeException(), isNull);
        await tester.tap(_action('back'));
        await tester.pumpAndSettle();
        expect(h.results, [null]);
        expect(find.text('Home'), findsOneWidget);
      } finally {
        await h.close();
      }
    });
  }

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets(
        'scanner adapts to $size and large text without clipped actions',
        (tester) async {
      final h = _ScannerHost(tester);
      try {
        final insets = size.width > size.height
            ? const EdgeInsets.fromLTRB(44, 24, 16, 16)
            : const EdgeInsets.only(top: 24, bottom: 20);
        await h.mount(size: size, textScale: 2, padding: insets);
        final page = Rect.fromLTRB(insets.left, insets.top,
            size.width - insets.right, size.height - insets.bottom);
        for (final id in ['back', 'album', 'flash', 'my-code']) {
          final bounds = tester.getRect(_action(id));
          expect(page.contains(bounds.topLeft), isTrue);
          expect(bounds.right, lessThanOrEqualTo(page.right));
          expect(bounds.bottom, lessThanOrEqualTo(page.bottom));
          expect(_action(id).hitTestable(), findsOneWidget);
        }
        if (size.width > size.height) {
          final instructionViewport = find.ancestor(
              of: find.text('请将镜头对准二维码进行扫描'),
              matching: find.byType(SingleChildScrollView));
          expect(instructionViewport, findsOneWidget);
          expect(tester.getRect(instructionViewport).bottom,
              lessThanOrEqualTo(tester.getRect(_action('my-code')).top),
              reason: 'The wrapped instruction cannot cover the QR shortcut');
        }
        expect(tester.takeException(), isNull,
            reason: 'Scanner labels and controls must not overflow');
      } finally {
        await h.close();
      }
    });
  }

  testWidgets(
      'flash requires camera permission and recovers after native failure',
      (tester) async {
    final h = _ScannerHost(tester);
    try {
      await h.mount(granted: false);
      await tester.tap(_action('flash'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.native.calls, isNot(contains('toggleFlash')));

      await h.native.permission(true);
      await tester.pumpAndSettle();
      h.native.flashFailure = PlatformException(code: 'flash-unavailable');
      await tester.tap(_action('flash'));
      await tester.pumpAndSettle();
      expect(h.native.flashOn, isFalse);
      expect(find.byType(FriendQrScanner), findsOneWidget);
      expect(tester.takeException(), isNull);

      h.native.flashFailure = null;
      await tester.tap(_action('flash'));
      await tester.pumpAndSettle();
      expect(h.native.flashOn, isTrue);
      await tester.tap(_action('flash'));
      await tester.pumpAndSettle();
      expect(h.native.flashOn, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close();
    }
  });

  testWidgets('devices without a flash never send native flash commands',
      (tester) async {
    final h = _ScannerHost(tester);
    h.native.hasFlash = false;
    try {
      await h.mount();
      await tester.tap(_action('flash'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.native.calls, isNot(contains('toggleFlash')));
      await h.native.recognize(_invite);
      await tester.pumpAndSettle();
      expect(h.results.single?['userID'], 'peer');
    } finally {
      await h.close();
    }
  });

  testWidgets('album cancellation pauses scan results and restores the camera',
      (tester) async {
    final pick = Completer<String?>();
    final gallery = _Gallery(pick: () => pick.future);
    final h = _ScannerHost(tester, gallery: gallery);
    try {
      await h.mount();
      h.native.cameraCalls.clear();
      await tester.tap(_action('album'));
      await tester.pump();
      expect(h.native.cameraCalls, contains('pauseCamera'));
      await h.native.recognize(_invite);
      await tester.pump();
      expect(h.results, isEmpty,
          reason: 'An in-flight camera result must not dismiss the picker');
      await tester.tap(_action('album'), warnIfMissed: false);
      await tester.pump();
      expect(gallery.pickCalls, 1,
          reason: 'Repeated taps must not open multiple native pickers');

      h.native.cameraCalls.clear();
      pick.complete(null);
      await tester.pumpAndSettle();
      expect(h.native.cameraCalls, contains('resumeCamera'));
      expect(gallery.paths, isEmpty);
      await h.native.recognize(_invite);
      await tester.pumpAndSettle();
      expect(h.results.single?['userID'], 'peer');
    } finally {
      if (!pick.isCompleted) pick.complete(null);
      await h.close();
    }
  });

  testWidgets(
      'invalid album code stays open and a valid link preserves its source',
      (tester) async {
    var code = 'openim://user/peer';
    final gallery = _Gallery(
      pick: () async => '/chosen.png',
      read: (_) async => code,
    );
    final h = _ScannerHost(tester, gallery: gallery);
    try {
      await h.mount();
      await tester.tap(_action('album'));
      await tester.pumpAndSettle();
      expect(find.byType(FriendQrScanner), findsOneWidget);
      expect(h.results, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(gallery.paths, ['/chosen.png']);

      code = _link;
      await tester.tap(_action('album'));
      await tester.pumpAndSettle();
      expect(h.results, [
        {'userID': 'album-peer', 'inviteCode': 'fi_album', 'source': 'link'}
      ]);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close();
    }
  });

  testWidgets('album decode completed after closing cannot navigate again',
      (tester) async {
    final decoded = Completer<String?>();
    final gallery = _Gallery(
      pick: () async => '/chosen.png',
      read: (_) => decoded.future,
    );
    final h = _ScannerHost(tester, gallery: gallery);
    try {
      await h.mount();
      await tester.tap(_action('album'));
      await tester.pump();
      expect(gallery.paths, ['/chosen.png']);
      await tester.tap(_action('back'));
      await tester.pumpAndSettle();
      expect(h.results, [null]);
      decoded.complete(_link);
      await tester.pumpAndSettle();
      expect(h.results, [null]);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      if (!decoded.isCompleted) decoded.complete(null);
      await h.close();
    }
  });

  testWidgets('album results wait for foreground and stop waiting when closed',
      (tester) async {
    for (final closeWhileWaiting in [false, true]) {
      final pick = Completer<String?>();
      final decoded = Completer<String?>();
      final gallery = _Gallery(
        pick: () => pick.future,
        read: (_) => decoded.future,
      );
      final h = _ScannerHost(tester, gallery: gallery);
      try {
        await h.mount();
        await tester.tap(_action('album'));
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();

        // Native pickers may deliver their selection before the app resumes.
        pick.complete('/chosen.png');
        await tester.pump();
        expect(gallery.paths, isEmpty,
            reason:
                'Image work must wait for the scanner to regain foreground');
        expect(h.results, isEmpty);

        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        await tester.pump();
        expect(gallery.paths, ['/chosen.png']);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        decoded.complete(_link);
        await tester.pump();
        expect(h.results, isEmpty,
            reason: 'A decoded invitation cannot navigate in the background');

        if (closeWhileWaiting) {
          await tester.tap(_action('back'));
          await tester.pumpAndSettle();
          expect(h.results, [null]);
        }
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(
          h.results,
          closeWhileWaiting
              ? [null]
              : [
                  {
                    'userID': 'album-peer',
                    'inviteCode': 'fi_album',
                    'source': 'link'
                  }
                ],
        );
        expect(find.text('Home'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        if (!pick.isCompleted) pick.complete(null);
        if (!decoded.isCompleted) decoded.complete(null);
        await h.close();
      }
    }
  });

  testWidgets('my QR route pauses scanner and returns to the same camera state',
      (tester) async {
    final h = _ScannerHost(tester);
    try {
      await h.mount();
      final scanner = tester.state(find.byType(FriendQrScanner));
      h.native.cameraCalls.clear();
      await tester.tap(_action('my-code'));
      await tester.pumpAndSettle();
      expect(find.text('My QR'), findsOneWidget);
      expect(h.native.cameraCalls, contains('pauseCamera'));
      await h.native.recognize(_invite);
      await tester.pump();
      expect(h.results, isEmpty);

      h.native.cameraCalls.clear();
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(FriendQrScanner)), same(scanner));
      expect(h.native.cameraCalls, contains('resumeCamera'));
      await h.native.recognize(_invite);
      await tester.pumpAndSettle();
      expect(h.results.single?['userID'], 'peer');
      expect(tester.takeException(), isNull);
    } finally {
      await h.close();
    }
  });

  testWidgets('invalid and repeated native codes produce only one valid result',
      (tester) async {
    final h = _ScannerHost(tester);
    try {
      await h.mount();
      await h.native.recognize('');
      await h.native.recognize('openim://user/peer');
      await h.native.recognize('https://example.com');
      await tester.pump();
      expect(h.results, isEmpty);
      expect(find.byType(FriendQrScanner), findsOneWidget);

      await Future.wait([
        h.native.recognize(_invite),
        h.native.recognize(_invite),
      ]);
      await tester.pumpAndSettle();
      expect(h.results, [
        {'userID': 'peer', 'inviteCode': 'fi_test', 'source': 'qrcode'}
      ]);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await h.close();
    }
  });
  testWidgets('export actual light and dark scanner pages', (tester) async {
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/msyh.ttc');
      if (await font.exists()) {
        final bytes = ByteData.sublistView(await font.readAsBytes());
        await (FontLoader('ScannerPreviewFont')..addFont(Future.value(bytes)))
            .load();
      }
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final images = <ui.Image>[];
    try {
      for (var index = 0; index < 2; index++) {
        final h = _ScannerHost(tester);
        try {
          await h.mount(dark: index == 1, previewFont: 'ScannerPreviewFont');
          await tester.pump();
          final boundary = h.previewKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image =
              (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
          images.add(image);
          canvas.drawImage(image, Offset(index * 390.0, 0), Paint());
        } finally {
          await h.close();
        }
      }
      final picture = recorder.endRecording();
      await tester.runAsync(() async {
        final combined = await picture.toImage(780, 844);
        try {
          final data =
              await combined.toByteData(format: ui.ImageByteFormat.png);
          final file = File(_previewOutput);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          for (var index = 0; index < images.length; index++) {
            final png =
                await images[index].toByteData(format: ui.ImageByteFormat.png);
            await File('${file.parent.path}/friend-qr-scanner-'
                    '${index == 0 ? 'light' : 'dark'}.png')
                .writeAsBytes(png!.buffer.asUint8List());
          }
        } finally {
          combined.dispose();
          picture.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    } finally {
      for (final image in images) {
        image.dispose();
      }
    }
  }, skip: _previewOutput.isEmpty);
}

class _Gallery extends FriendQrGalleryService {
  _Gallery({Future<String?> Function()? pick, this.read})
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

class _ScannerHost {
  _ScannerHost(this.tester, {FriendQrGalleryService? gallery})
      : native = NativeQrScanner(tester),
        gallery = gallery ?? _Gallery() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  }

  final WidgetTester tester;
  final NativeQrScanner native;
  final FriendQrGalleryService gallery;
  final navigator = GlobalKey<NavigatorState>();
  final previewKey = GlobalKey();
  final results = <Map<String, String>?>[];

  Future<void> mount({
    bool dark = false,
    bool granted = true,
    Size size = const Size(390, 844),
    double textScale = 1,
    String? previewFont,
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
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
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
                          results.add(await Navigator.of(context)
                              .push<Map<String, String>>(MaterialPageRoute(
                            builder: (_) => FriendQrScanner(
                              gallery: gallery,
                              onMyQrTap: () async {
                                await navigator.currentState!.push<void>(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const Scaffold(body: Text('My QR')),
                                  ),
                                );
                              },
                            ),
                          )));
                        },
                        child: const Text('Open scanner'),
                      ),
                    ]),
                  )),
        )));
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
    expect(find.byType(QRView), findsOneWidget);
    expect(native.channel, isNotNull);
    await native.permission(granted);
    await tester.pumpAndSettle();
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
