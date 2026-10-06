import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/favorites/media/favorite_asset_preview.dart';
import 'package:openim/pages/favorites/media/favorite_preview_loader.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/favorite_ui_test_support.dart';

class _Video extends VideoPlayerPlatform {
  int plays = 0;
  bool released = false;
  DataSource? source;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    source = options.dataSource;
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int id) => Stream.value(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 2),
      size: const Size(160, 240)));
  @override
  Future<void> setLooping(int id, bool value) async {}
  @override
  Future<void> setVolume(int id, double value) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double value) async {}
  @override
  Future<void> play(int id) async {
    plays++;
  }

  @override
  Future<void> pause(int id) async {}
  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox(key: ValueKey('preview-video-frame'));
  @override
  Future<void> dispose(int id) async {
    released = true;
  }
}

class _Loader extends FavoritePreviewLoader {
  @override
  Future<File> load(FavoriteRepository repository, FavoriteItem item,
          FavoriteAsset asset, String scope,
          {dynamic onProgress}) async =>
      File('openim_common/assets/images/ic_archive_99chat.png');
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets(
      'video preview uses verified local source with explicit playback and releases',
      (tester) async {
    final previous = VideoPlayerPlatform.instance;
    final platform = _Video();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    final repo = FavoriteUiRepository();
    addTearDown(repo.dispose);
    const asset = FavoriteAsset(
        id: 'video',
        mimeType: 'video/mp4',
        sizeBytes: 1,
        sha256: 'fake-checksum');
    const item = FavoriteItem(
        id: 'fav-video',
        kind: FavoriteKind.video,
        title: '',
        version: 1,
        status: FavoriteStatus.ready);
    await tester.runAsync(() async {
      await tester.pumpWidget(favoriteUiHost(Scaffold(
          body: FavoriteAssetPreview(
              repository: repo,
              item: item,
              asset: asset,
              loaderFactory: _Loader.new))));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preview-video-frame')), findsOneWidget);
    expect(platform.source!.sourceType, DataSourceType.file);
    expect(platform.plays, 0);
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(platform.plays, 1);
    repo.active = false;
    repo.notifyListeners();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(find.byKey(const ValueKey('preview-video-frame')), findsNothing);
    expect(platform.released, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
