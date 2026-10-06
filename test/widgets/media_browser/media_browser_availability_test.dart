import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/media_browser/local_media_availability.dart';
import 'package:openim_common/src/widgets/media_browser/media_grid_thumbnail.dart';

import '../../support/performance/render_test_fakes.dart';

class _File extends Fake implements File {
  _File(this.path, this.available);
  @override
  final String path;
  Future<bool> available;
  int checks = 0;
  @override
  Future<bool> exists() {
    checks++;
    return available;
  }

  @override
  bool existsSync() => throw StateError('Synchronous disk check in render');
  @override
  Future<int> length() async => renderTestPng().length;
  @override
  Future<Uint8List> readAsBytes() async => renderTestPng();
}

class _RecordedAvailability extends LocalMediaAvailability {
  final paths = <String>[];
  @override
  Future<bool> exists(File file) {
    paths.add(file.path);
    return Future.value(true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  test('availability deduplicates one path and handles asynchronous failure',
      () async {
    final cache = LocalMediaAvailability();
    final request = Completer<bool>();
    final file = _File('cached.png', request.future);
    final first = cache.exists(file);
    expect(cache.exists(file), same(first));
    expect(file.checks, 1);
    request.complete(true);
    expect(await first, isTrue);
    cache.clear();
    expect(await cache.exists(file), isTrue);
    expect(file.checks, 2);
    final failed = _File('failed.png', Future.error(StateError('Unavailable')));
    expect(await cache.exists(failed), isFalse);
  });

  testWidgets(
      'browser never checks files synchronously and reuses async result',
      (tester) async {
    final request = Completer<bool>();
    final file = _File('browser.png', request.future);
    final source = MediaSource(file: file, thumbnail: '', tag: 'file');
    Widget browser() =>
        renderTestHost(MediaBrowser(initialIndex: 0, sources: [source]));
    await tester.pumpWidget(browser());
    expect(file.checks, 1);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    await tester.pumpWidget(browser());
    expect(file.checks, 1);
    request.complete(true);
    await tester.pumpAndSettle();
    final full = tester.widget<ExtendedImage>(find.byType(ExtendedImage));
    expect(full.image, isA<ExtendedFileImageProvider>());
    expect(full.image, isNot(isA<ResizeImage>()),
        reason: 'Full-screen original quality must remain unrestricted');
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();
    final thumbnail = tester.widget<Image>(find.byType(Image));
    final provider = thumbnail.image as ResizeImage;
    expect(provider.width, greaterThan(0));
    expect(provider.height, greaterThan(0));
    expect(provider.policy, ResizeImagePolicy.fit);
    expect(file.checks, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  test('invalidated pending checks cannot overwrite a fresh result', () async {
    final cache = LocalMediaAvailability();
    final old = Completer<bool>();
    final file = _File('changing.png', old.future);
    final first = cache.exists(file);
    cache.invalidateMissing();
    file.available = Future.value(true);
    final next = cache.exists(file);
    expect(await next, isTrue);
    old.complete(false);
    expect(await first, isFalse);
    cache.invalidateMissing();
    expect(cache.exists(file), same(next));
    expect(file.checks, 2);
  });

  testWidgets('grid uses thumbnail before original and sizes pixels by DPR',
      (tester) async {
    final thumb = File('openim_common/assets/images/ic_archive_99chat.png');
    final availability = _RecordedAvailability();
    final original = _File('unused-original.png', Future.value(true));
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(renderTestHost(Center(
      child: SizedBox(
        width: 120,
        height: 90,
        child: MediaGridThumbnail(
          availability: availability,
          source: MediaSource(file: original, thumbnail: thumb.path),
        ),
      ),
    )));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as ResizeImage;
    expect(provider.width, 240);
    expect(provider.height, 180);
    expect((provider.imageProvider as FileImage).file.path, thumb.path);
    expect(availability.paths, [thumb.path]);
    expect(original.checks, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('updated source retries a formerly missing local download',
      (tester) async {
    final file = _File('download.png', Future.value(false));
    await tester.pumpWidget(renderTestHost(MediaBrowser(
      initialIndex: 0,
      sources: [MediaSource(file: file, thumbnail: '', loading: true)],
    )));
    await tester.pump();
    expect(file.checks, 1);
    file.available = Future.value(true);
    await tester.pumpWidget(renderTestHost(MediaBrowser(
      initialIndex: 0,
      sources: [MediaSource(file: file, thumbnail: '')],
    )));
    await tester.pumpAndSettle();
    expect(file.checks, 2);
    final image = tester.widget<ExtendedImage>(find.byType(ExtendedImage));
    expect(image.image, isA<ExtendedFileImageProvider>());
    expect(image.image, isNot(isA<ResizeImage>()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('local check completing after browser disposal is ignored',
      (tester) async {
    final request = Completer<bool>();
    final file = _File('late.png', request.future);
    await tester.pumpWidget(renderTestHost(MediaBrowser(
        initialIndex: 0,
        sources: [MediaSource(file: file, thumbnail: '', tag: 'late')])));
    await tester.pumpWidget(const SizedBox.shrink());
    request.complete(true);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery selection jumps the retained page controller',
      (tester) async {
    final pages = <int>[];
    await tester.pumpWidget(renderTestHost(MediaBrowser(
      initialIndex: 0,
      sources: [
        MediaSource(bytes: renderTestPng(), thumbnail: '', tag: 'first'),
        MediaSource(bytes: renderTestPng(), thumbnail: '', tag: 'second'),
      ],
      onPageChanged: pages.add,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MediaGridThumbnail).at(1));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.textContaining('2/2'), findsOneWidget);
    expect(pages, contains(1));
    expect(tester.takeException(), isNull);
  });
}
