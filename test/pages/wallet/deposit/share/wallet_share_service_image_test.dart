import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openim/pages/wallet/wallet_share_service.dart';
// Test the installed plugin boundary without launching an external application.
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

class _ImageSharePlatform extends SharePlatform {
  int calls = 0;
  List<XFile>? files;
  String? text;
  String? subject;
  Rect? origin;
  List<String>? names;
  Object? error;
  ShareResult result =
      const ShareResult('image-target', ShareResultStatus.success);

  @override
  Future<ShareResult> shareXFiles(
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    calls++;
    this.files = files;
    this.subject = subject;
    this.text = text;
    origin = sharePositionOrigin;
    names = fileNameOverrides;
    if (error != null) throw error!;
    return result;
  }
}

class _ObservedCapture extends SingleChildRenderObjectWidget {
  const _ObservedCapture({
    super.key,
    required super.child,
    this.onCaptured,
  });

  final VoidCallback? onCaptured;

  @override
  _ObservedCaptureBoundary createRenderObject(BuildContext context) =>
      _ObservedCaptureBoundary(onCaptured);

  @override
  void updateRenderObject(
          BuildContext context, _ObservedCaptureBoundary renderObject) =>
      renderObject.onCaptured = onCaptured;
}

class _ObservedCaptureBoundary extends RenderRepaintBoundary {
  _ObservedCaptureBoundary(this.onCaptured);
  VoidCallback? onCaptured;

  @override
  Future<ui.Image> toImage({double pixelRatio = 1.0}) async {
    final image = await super.toImage(pixelRatio: pixelRatio);
    onCaptured?.call();
    return image;
  }
}

Future<BuildContext> _card(WidgetTester tester, GlobalKey boundary,
    {VoidCallback? onCaptured, Widget? content}) async {
  late BuildContext context;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (hostContext) {
        context = hostContext;
        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 24, top: 32),
            child: _ObservedCapture(
              key: boundary,
              onCaptured: onCaptured,
              child: SizedBox(
                width: 180,
                height: 120,
                child: content ??
                    const ColoredBox(
                      color: Color(0xFFFFFFFF),
                      child: Center(child: Text('Rendered deposit card')),
                    ),
              ),
            ),
          ),
        );
      }),
    ),
  ));
  await tester.pump();
  return context;
}

Future<void> _expectTransparentCapture(
    WidgetTester tester, GlobalKey boundary) async {
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 3.0);
    try {
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(pixels!.getUint8(3), 0);
    } finally {
      image.dispose();
    }
  });
}

void _expectOpaquePngAndJpeg(Uint8List bytes, Color background) {
  final png = img.decodePng(bytes)!;
  expect(png.width, 540);
  expect(png.height, 360);
  expect(png.every((pixel) => pixel.a == 255), isTrue,
      reason: 'Every exported pixel must stay opaque after JPEG conversion.');
  final rgb = background.toARGB32();
  final expected = [(rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255];
  final corners = [(0, 0), (539, 0), (0, 359), (539, 359)];
  for (final corner in corners) {
    final pixel = png.getPixel(corner.$1, corner.$2);
    expect([pixel.r, pixel.g, pixel.b, pixel.a], [...expected, 255]);
  }
  final mainContent = png.getPixel(270, 180);
  expect([mainContent.r, mainContent.g, mainContent.b, mainContent.a],
      [30, 144, 255, 255]);

  // Match the Android gallery plugin's PNG-to-JPEG conversion. A tiny JPEG
  // colour-rounding tolerance is allowed while black transparent corners are not.
  final jpeg = img.decodeJpg(img.encodeJpg(png, quality: 100))!;
  expect(jpeg.width, png.width);
  expect(jpeg.height, png.height);
  for (final corner in corners) {
    final pixel = jpeg.getPixel(corner.$1, corner.$2);
    expect(pixel.r, closeTo(expected[0], 3));
    expect(pixel.g, closeTo(expected[1], 3));
    expect(pixel.b, closeTo(expected[2], 3));
  }
  final jpegContent = jpeg.getPixel(270, 180);
  expect(jpegContent.r, closeTo(30, 3));
  expect(jpegContent.g, closeTo(144, 3));
  expect(jpegContent.b, closeTo(255, 3));
}

void _testMobileWidgets(String name, WidgetTesterCallback body) {
  testWidgets(name, (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(tester);
    } finally {
      // Flutter checks this invariant before package:test runs tearDown.
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharePlatform originalPlatform;
  late _ImageSharePlatform platform;
  late WalletShareService service;
  const gallery = MethodChannel('image_gallery_saver_plus');
  late int galleryCalls;
  Map<Object?, Object?>? savedImage;
  setUp(() {
    originalPlatform = SharePlatform.instance;
    SharePlatform.instance = platform = _ImageSharePlatform();
    service = WalletShareService();
    galleryCalls = 0;
    savedImage = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(gallery, (call) async {
      galleryCalls++;
      savedImage = Map<Object?, Object?>.from(call.arguments as Map);
      return {'isSuccess': true};
    });
  });
  tearDown(() {
    SharePlatform.instance = originalPlatform;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(gallery, null);
  });

  _testMobileWidgets(
      'system share exports one actual PNG card and its popover origin',
      (tester) async {
    final boundary = GlobalKey();
    final context = await _card(tester, boundary);
    final result = await tester.runAsync(() =>
        service.shareSystemImage(context, boundary, isCurrent: () => true));

    expect(result, WalletSystemShareResult.success);
    expect(platform.calls, 1);
    expect(platform.files, hasLength(1));
    final image = platform.files!.single;
    expect(image.mimeType, 'image/png');
    expect(platform.text, isNull);
    expect(platform.subject, isNull);
    expect(platform.names, hasLength(1));
    expect(
        platform.names!.single, matches(RegExp(r'^99Chat_deposit_\d+\.png$')));
    expect(platform.origin, const Rect.fromLTWH(24, 32, 180, 120));
    final Uint8List bytes = (await tester.runAsync(image.readAsBytes))!;
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          expect(frame.image.width, 540);
          expect(frame.image.height, 360);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    });
  });

  _testMobileWidgets('an already stale deposit never launches system sharing',
      (tester) async {
    final boundary = GlobalKey();
    final context = await _card(tester, boundary);
    final result = await service.shareSystemImage(context, boundary,
        isCurrent: () => false);
    expect(result, WalletSystemShareResult.dismissed);
    expect(platform.calls, 0);
  });

  _testMobileWidgets(
      'a deposit invalidated during capture never launches sharing',
      (tester) async {
    final boundary = GlobalKey();
    final context = await _card(tester, boundary);
    var checks = 0;
    final result = await tester.runAsync(() => service.shareSystemImage(
          context,
          boundary,
          isCurrent: () => ++checks == 1,
        ));
    expect(checks, greaterThan(1));
    expect(result, WalletSystemShareResult.dismissed);
    expect(platform.calls, 0);
  });

  _testMobileWidgets('an unmounted preview never launches sharing',
      (tester) async {
    final boundary = GlobalKey();
    final context = await _card(tester, boundary);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(context.mounted, isFalse);
    final result = await service.shareSystemImage(context, boundary,
        isCurrent: () => true);
    expect(result, WalletSystemShareResult.dismissed);
    expect(platform.calls, 0);
  });

  _testMobileWidgets(
      'a missing repaint boundary returns failure without sharing',
      (tester) async {
    final context = await _card(tester, GlobalKey());
    final result = await service.shareSystemImage(context, GlobalKey(),
        isCurrent: () => true);
    expect(result, WalletSystemShareResult.failed);
    expect(platform.calls, 0);
  });

  for (final status in [
    ShareResultStatus.dismissed,
    ShareResultStatus.unavailable
  ]) {
    _testMobileWidgets('native $status is not reported as a successful share',
        (tester) async {
      platform.result = ShareResult('', status);
      final boundary = GlobalKey();
      final context = await _card(tester, boundary);
      final result = await tester.runAsync(() =>
          service.shareSystemImage(context, boundary, isCurrent: () => true));
      expect(
        result,
        status == ShareResultStatus.dismissed
            ? WalletSystemShareResult.dismissed
            : WalletSystemShareResult.unavailable,
      );
      expect(platform.calls, 1);
    });
  }

  _testMobileWidgets('missing native plugin returns unavailable',
      (tester) async {
    platform.error = MissingPluginException();
    final boundary = GlobalKey();
    final context = await _card(tester, boundary);
    final result = await tester.runAsync(() =>
        service.shareSystemImage(context, boundary, isCurrent: () => true));
    expect(result, WalletSystemShareResult.unavailable);
  });

  _testMobileWidgets(
      'native share failure returns failure without claiming success',
      (tester) async {
    platform.error = PlatformException(code: 'share-failed');
    final boundary = GlobalKey();
    final context = await _card(tester, boundary);
    final result = await tester.runAsync(() =>
        service.shareSystemImage(context, boundary, isCurrent: () => true));
    expect(result, WalletSystemShareResult.failed);
  });

  _testMobileWidgets('unsupported platforms never export or launch sharing',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final boundary = GlobalKey();
    final context = await _card(tester, boundary);
    final result = await service.shareSystemImage(context, boundary,
        isCurrent: () => true);
    expect(result, WalletSystemShareResult.unavailable);
    expect(platform.calls, 0);
  });

  _testMobileWidgets(
      'image saving still supports callers without a scope callback',
      (tester) async {
    service = WalletShareService(requestPhotoPermission: (_) async => true);
    final boundary = GlobalKey();
    final context = await _card(tester, boundary);
    final result =
        await tester.runAsync(() => service.saveQrImg(context, boundary));
    expect(result, WalletSaveImgResult.success);
    expect(galleryCalls, 1);
    final bytes = savedImage!['imageBytes'] as Uint8List;
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(savedImage!['name'], startsWith('wallet_receive_'));
    expect(savedImage!['quality'], 100);
    expect(platform.calls, 0);
  });

  _testMobileWidgets(
      'stale image saving never requests permission or writes a gallery image',
      (tester) async {
    var permissionCalls = 0;
    service = WalletShareService(requestPhotoPermission: (_) async {
      permissionCalls++;
      return true;
    });
    final boundary = GlobalKey();
    final context = await _card(tester, boundary);
    final result =
        await service.saveQrImg(context, boundary, isCurrent: () => false);
    expect(result, WalletSaveImgResult.unknown);
    expect(permissionCalls, 0);
    expect(galleryCalls, 0);
  });

  _testMobileWidgets(
      'image saving stops when its scope expires while permission is pending',
      (tester) async {
    final permission = Completer<bool>();
    var permissionCalls = 0;
    var current = true;
    service = WalletShareService(requestPhotoPermission: (_) {
      permissionCalls++;
      return permission.future;
    });
    final boundary = GlobalKey();
    final context = await _card(tester, boundary);
    final result = await tester.runAsync(() async {
      final pending =
          service.saveQrImg(context, boundary, isCurrent: () => current);
      expect(permissionCalls, 1);
      current = false;
      permission.complete(true);
      return pending;
    });
    expect(result, WalletSaveImgResult.unknown);
    expect(galleryCalls, 0);
  });

  _testMobileWidgets(
      'image saving stops when its scope expires during the paint delay',
      (tester) async {
    var current = true;
    var captured = false;
    service = WalletShareService(requestPhotoPermission: (_) async => true);
    final boundary = GlobalKey();
    final context =
        await _card(tester, boundary, onCaptured: () => captured = true);
    final result = await tester.runAsync(() async {
      final pending =
          service.saveQrImg(context, boundary, isCurrent: () => current);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      current = false;
      return pending;
    });
    expect(result, WalletSaveImgResult.unknown);
    expect(captured, isFalse);
    expect(galleryCalls, 0);
  });

  _testMobileWidgets('image saving checks scope again after actual PNG capture',
      (tester) async {
    var current = true;
    var captured = false;
    service = WalletShareService(requestPhotoPermission: (_) async => true);
    final boundary = GlobalKey();
    final context = await _card(tester, boundary, onCaptured: () {
      captured = true;
      current = false;
    });
    final result = await tester.runAsync(
        () => service.saveQrImg(context, boundary, isCurrent: () => current));
    expect(captured, isTrue);
    expect(result, WalletSaveImgResult.unknown);
    expect(galleryCalls, 0);
  });

  _testMobileWidgets('unmounted image saving never requests permission',
      (tester) async {
    var permissionCalls = 0;
    service = WalletShareService(requestPhotoPermission: (_) async {
      permissionCalls++;
      return true;
    });
    final boundary = GlobalKey();
    final context = await _card(tester, boundary);
    await tester.pumpWidget(const SizedBox.shrink());
    final result =
        await service.saveQrImg(context, boundary, isCurrent: () => true);
    expect(result, WalletSaveImgResult.unknown);
    expect(permissionCalls, 0);
    expect(galleryCalls, 0);
  });

  for (final background in [
    const Color(0x80FFFFFF),
    const Color(0x002A2D33),
  ]) {
    for (final sharing in [false, true]) {
      _testMobileWidgets(
          '${sharing ? 'sharing' : 'saving'} flattens rounded transparency with background=${background.toARGB32()}',
          (tester) async {
        service = WalletShareService(requestPhotoPermission: (_) async => true);
        final boundary = GlobalKey();
        final context = await _card(
          tester,
          boundary,
          content: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: const ColoredBox(color: Color(0xFF1E90FF)),
          ),
        );
        await _expectTransparentCapture(tester, boundary);
        late Uint8List bytes;
        if (sharing) {
          final result = await tester.runAsync(() => service.shareSystemImage(
                context,
                boundary,
                isCurrent: () => true,
                backgroundColor: background,
              ));
          expect(result, WalletSystemShareResult.success);
          expect(platform.calls, 1);
          bytes = (await tester.runAsync(platform.files!.single.readAsBytes))!;
        } else {
          final result = await tester.runAsync(() => service.saveQrImg(
                context,
                boundary,
                isCurrent: () => true,
                backgroundColor: background,
              ));
          expect(result, WalletSaveImgResult.success);
          expect(galleryCalls, 1);
          bytes = savedImage!['imageBytes'] as Uint8List;
        }
        _expectOpaquePngAndJpeg(bytes, background);
      });
    }
  }
}
