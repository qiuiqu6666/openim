import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/moments/moments_media_preview.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';

import '../../../support/performance/render_test_fakes.dart';

const _post = MomentPost(
  momentId: 'preview',
  author: renderTestUser,
  mediaList: [MomentMedia(mediaId: 'first'), MomentMedia(mediaId: 'second')],
);

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<MomentsRepository> _pumpPreview(WidgetTester tester, RenderTestApi api,
    {int initialIndex = 0}) async {
  final repository = renderTestRepository(api);
  repository.applyPost(_post);
  addTearDown(repository.dispose);
  await tester.pumpWidget(renderTestHost(MomentsMediaPreview(
      repository: repository, post: _post, initialIndex: initialIndex)));
  await _frames(tester);
  return repository;
}

void main() {
  tearDown(Get.reset);

  testWidgets(
      'selected second original starts first and displays before thumbs',
      (tester) async {
    final slowThumb = Completer<Uint8List>();
    final primary = renderTestPng();
    final api = RenderTestApi()
      ..mediaWork =
          (media, thumbnail) async => thumbnail ? slowThumb.future : primary;
    await _pumpPreview(tester, api, initialIndex: 1);
    expect(api.mediaCalls, ['second:false', 'first:true']);
    expect(find.byType(MediaBrowser), findsOneWidget);
    final browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
    expect(browser.sources[1].bytes, same(primary));
    expect(browser.sources[0].loading, isTrue);
    expect(browser.sources[0].url, isNull);
    slowThumb.complete(renderTestPng());
    await _frames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed unrelated thumbnail leaves primary and retries that image',
      (tester) async {
    final recovered = renderTestPng();
    final api = RenderTestApi()
      ..mediaWork = (media, thumbnail) async {
        if (thumbnail) throw StateError('Thumbnail unavailable');
        return recovered;
      };
    await _pumpPreview(tester, api);
    expect(find.byType(MediaBrowser), findsOneWidget);
    expect(find.text('Could not load photos'), findsNothing);
    var browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
    expect(browser.sources[1].loading, isFalse);
    expect(browser.sources[1].onRetry, isNotNull);
    browser.sources[1].onRetry!();
    await _frames(tester);
    browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
    expect(browser.sources[1].bytes, same(recovered));
    expect(api.mediaCalls, ['first:false', 'second:true', 'second:false']);
  });

  testWidgets('late thumbnail cannot replace upgraded full image or reset page',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lateThumb = Completer<Uint8List>();
    final full = renderTestPng();
    final api = RenderTestApi()
      ..mediaWork =
          (media, thumbnail) async => thumbnail ? lateThumb.future : full;
    await _pumpPreview(tester, api);
    await tester.drag(
        find.byType(ExtendedImageGesturePageView), const Offset(-550, 0));
    await _frames(tester);
    expect(api.mediaCalls, ['first:false', 'second:true', 'second:false']);
    expect(find.textContaining('2/2'), findsOneWidget);
    lateThumb.complete(renderTestPng());
    await tester.pumpAndSettle();
    final browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
    expect(browser.sources[1].bytes, same(full));
    expect(find.textContaining('2/2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late background thumb is discarded after revoke and dispose',
      (tester) async {
    final pending = Completer<Uint8List>();
    final bytes = renderTestPng();
    final api = RenderTestApi()
      ..mediaWork = (media, thumbnail) async =>
          thumbnail ? pending.future : renderTestPng();
    final repository = await _pumpPreview(tester, api);
    repository.resetSession();
    await tester.pump();
    expect(find.byType(MediaBrowser), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(bytes);
    await _frames(tester);
    expect(
        PaintingBinding.instance.imageCache
            .statusForKey(ExtendedMemoryImageProvider(bytes))
            .untracked,
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nine photos prefetch only the selected page neighbors',
      (tester) async {
    final api = RenderTestApi();
    final repository = renderTestRepository(api);
    final post = MomentPost(
        momentId: 'nine',
        author: renderTestUser,
        mediaList: List.generate(9, (i) => MomentMedia(mediaId: 'photo-$i')));
    repository.applyPost(post);
    addTearDown(repository.dispose);
    await tester.pumpWidget(renderTestHost(MomentsMediaPreview(
        repository: repository, post: post, initialIndex: 4)));
    await _frames(tester);
    expect(api.mediaCalls, ['photo-4:false', 'photo-3:true', 'photo-5:true']);
    final browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
    browser.onPageChanged!(5);
    await _frames(tester);
    expect(api.mediaCalls, [
      'photo-4:false',
      'photo-3:true',
      'photo-5:true',
      'photo-5:false',
      'photo-6:true'
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial missing post never starts a protected download',
      (tester) async {
    final api = RenderTestApi();
    final repository = renderTestRepository(api);
    addTearDown(repository.dispose);
    await tester.pumpWidget(renderTestHost(MomentsMediaPreview(
        repository: repository, post: _post, initialIndex: 0)));
    await _frames(tester);
    expect(api.mediaCalls, isEmpty);
    expect(find.text('Content unavailable'), findsOneWidget);
    expect(find.byType(MediaBrowser), findsNothing);
  });

  testWidgets('resource replacement drops a pending old original',
      (tester) async {
    final pending = Completer<Uint8List>();
    final oldBytes = renderTestPng();
    final nextBytes = renderTestPng();
    final api = RenderTestApi()
      ..mediaWork = (media, thumbnail) async =>
          media.mediaId == 'old' ? pending.future : nextBytes;
    final repository = renderTestRepository(api);
    addTearDown(repository.dispose);
    const old = MomentPost(
        momentId: 'same',
        author: renderTestUser,
        mediaList: [MomentMedia(mediaId: 'old', contentPath: '/old')]);
    const next = MomentPost(
        momentId: 'same',
        author: renderTestUser,
        version: 2,
        mediaList: [MomentMedia(mediaId: 'new', contentPath: '/new')]);
    repository.applyPost(old);
    await tester.pumpWidget(renderTestHost(MomentsMediaPreview(
        repository: repository, post: old, initialIndex: 0)));
    await _frames(tester);
    repository.applyPost(next);
    await tester.pumpWidget(renderTestHost(MomentsMediaPreview(
        repository: repository, post: next, initialIndex: 0)));
    await _frames(tester);
    pending.complete(oldBytes);
    await _frames(tester);
    final browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
    expect(browser.sources.single.bytes, same(nextBytes));
    expect(api.mediaCalls, ['old:false', 'new:false']);
    expect(
        PaintingBinding.instance.imageCache
            .statusForKey(ExtendedMemoryImageProvider(oldBytes))
            .untracked,
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed preview paints an accessible back control and pops its route',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = RenderTestApi()
      ..mediaWork =
          (_, __) async => throw const MomentsException('unavailable');
    final repository = renderTestRepository(api)..applyPost(_post);
    addTearDown(repository.dispose);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(renderTestHost(Builder(
        builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => RepaintBoundary(
                    key: boundaryKey,
                    child: MomentsMediaPreview(
                        repository: repository,
                        post: _post,
                        initialIndex: 0)))),
            child: const Text('Open photos')))));
    await tester.tap(find.text('Open photos'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load photos'), findsOneWidget);
    final back = find.byTooltip('Back').hitTestable();
    expect(back, findsOneWidget);
    final rect = tester.getRect(back);
    expect(rect.width, greaterThanOrEqualTo(44));
    expect(rect.height, greaterThanOrEqualTo(44));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(100));
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final headerPixels = await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        var backPixels = 0, titlePixels = 0;
        for (var y = 0; y < 56; y++) {
          for (var x = 0; x < 140; x++) {
            final offset = (y * image.width + x) * 4;
            if (bytes[offset] > 160 &&
                bytes[offset + 1] > 160 &&
                bytes[offset + 2] > 160) {
              if (x < 48) {
                backPixels++;
              } else {
                titlePixels++;
              }
            }
          }
        }
        return [backPixels, titlePixels];
      } finally {
        image.dispose();
      }
    });
    expect(headerPixels![0], greaterThan(20));
    expect(headerPixels[1], greaterThan(40));
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();
    expect(find.text('Open photos'), findsOneWidget);
    expect(find.text('Could not load photos'), findsNothing);
  });
}
