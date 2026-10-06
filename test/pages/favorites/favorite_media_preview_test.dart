import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/favorites/media/favorite_asset_preview.dart';
import 'package:openim/pages/favorites/media/favorite_item_thumbnail.dart';
import 'package:openim/pages/favorites/media/favorite_preview_loader.dart';
import 'package:openim/services/favorite_repository.dart';

import 'support/favorite_ui_test_support.dart';

class _RealHttp extends HttpOverrides {}

Dio _client() => Dio()
  ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => _RealHttp().createHttpClient(null));

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
FavoriteAsset _asset([String mime = 'image/png']) => FavoriteAsset(
    id: 'original-1',
    mimeType: mime,
    sizeBytes: _png.length,
    sha256: sha256.convert(_png).toString());
FavoriteItem _item([String kind = 'image']) => FavoriteItem(
    id: 'fav-1',
    kind: FavoriteKind.parse(kind),
    title: '测试原件',
    version: 1,
    status: FavoriteStatus.ready,
    assets: [_asset()],
    content: FavoriteContent(
        kind: FavoriteKind.parse(kind),
        blocks: [FavoriteBlock(id: 'b1', type: kind, assetID: 'original-1')]));

class _Repository extends FavoriteUiRepository {
  _Repository(this.grant) : super(initial: [_item()]);
  FavoriteDownload grant;
  Completer<FavoriteDownload>? delayed;
  @override
  Future<FavoriteDownload> assetAccess(String id, String assetID) async =>
      delayed == null ? grant : delayed!.future;
}

class _LocalLoader extends FavoritePreviewLoader {
  _LocalLoader(this.original);
  final File original;
  bool closed = false;
  @override
  Future<File> load(FavoriteRepository repository, FavoriteItem item,
          FavoriteAsset asset, String scope,
          {ProgressCallback? onProgress}) async =>
      original;
  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpServer server;
  late _Repository repository;
  var status = 200;
  late List<int> body;
  final headers = <HttpHeaders>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('favorite-preview-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    status = 200;
    body = _png;
    headers.clear();
    server.listen((request) async {
      headers.add(request.headers);
      request.response.statusCode = status;
      if (status == 302) request.response.headers.set('location', '/redirect');
      request.response.add(body);
      await request.response.close();
    });
    repository = _Repository(FavoriteDownload(
        assetID: 'original-1',
        url: Uri.parse('http://127.0.0.1:${server.port}/original'),
        sizeBytes: _png.length,
        sha256: sha256.convert(_png).toString(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1))));
  });
  tearDown(() async {
    repository.dispose();
    await server.close(force: true);
    expect(
        root.absolute.path.startsWith(
            '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}'),
        isTrue);
    await root.delete(recursive: true);
  });

  test('verified original has no business credentials and is removed on close',
      () async {
    final loader = FavoritePreviewLoader(
        client: _client(), temporaryRoot: () async => root);
    final file = await loader.load(
        repository, _item(), _asset(), repository.sessionScope);
    expect(await file.readAsBytes(), _png);
    expect(headers.single.value('token'), isNull);
    expect(headers.single.value('authorization'), isNull);
    expect(headers.single.value('cookie'), isNull);
    await loader.close();
    expect(await file.exists(), isFalse);
    expect(await root.list().toList(), isEmpty);
  });

  test('tampered same-size original is rejected and temporary bytes removed',
      () async {
    body = List.of(_png)..[0] = 0;
    final loader = FavoritePreviewLoader(
        client: _client(), temporaryRoot: () async => root);
    await expectLater(
        loader.load(repository, _item(), _asset(), repository.sessionScope),
        throwsA(isA<FavoriteApiException>()));
    await loader.close();
    expect(await root.list().toList(), isEmpty);
  });

  test('redirect does not follow another media URL', () async {
    status = 302;
    final loader = FavoritePreviewLoader(
        client: _client(), temporaryRoot: () async => root);
    await expectLater(
        loader.load(repository, _item(), _asset(), repository.sessionScope),
        throwsA(isA<DioException>()));
    expect(headers, hasLength(1));
    await loader.close();
    expect(await root.list().toList(), isEmpty);
  });

  test('expired lease is rejected before downloading', () async {
    repository.grant = FavoriteDownload(
        assetID: 'original-1',
        url: repository.grant.url,
        sizeBytes: _png.length,
        sha256: sha256.convert(_png).toString(),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)));
    final loader = FavoritePreviewLoader(
        client: _client(), temporaryRoot: () async => root);
    await expectLater(
        loader.load(repository, _item(), _asset(), repository.sessionScope),
        throwsA(isA<FavoriteApiException>()));
    expect(headers, isEmpty);
    await loader.close();
  });

  test(
      'account switch while obtaining access never downloads previous account media',
      () async {
    repository.delayed = Completer<FavoriteDownload>();
    final loader = FavoritePreviewLoader(
        client: _client(), temporaryRoot: () async => root);
    final work =
        loader.load(repository, _item(), _asset(), repository.sessionScope);
    final expected = expectLater(work, throwsA(isA<FavoriteApiException>()));
    repository.active = false;
    repository.delayed!.complete(repository.grant);
    await expected;
    expect(headers, isEmpty);
    await loader.close();
  });

  testWidgets(
      'image zoom opens without sending and account switch hides original',
      (tester) async {
    final original = (await tester
        .runAsync(() => File('${root.path}/image.png').writeAsBytes(_png)))!;
    final loader = _LocalLoader(original);
    await tester.runAsync(() async {
      await tester.pumpWidget(favoriteUiHost(Scaffold(
          body: FavoriteAssetPreview(
              repository: repository,
              item: _item(),
              asset: _asset(),
              loaderFactory: () => loader))));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorite-image-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('favorite-image-close')), findsOneWidget);
    expect(repository.saves, 0);
    expect(repository.detailCalls, 0);
    repository.active = false;
    repository.notifyListeners();
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(loader.closed, isTrue);
    await tester.tap(find.byKey(const ValueKey('favorite-image-close')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('video thumbnail selects cover without downloading the video', () {
    final video = FavoriteAsset(
        id: 'video',
        mimeType: 'video/mp4',
        sizeBytes: 10000000,
        sha256: '0' * 64,
        coverAssetID: 'original-1');
    final value = FavoriteItem(
        id: 'video-item',
        version: 1,
        kind: FavoriteKind.video,
        title: '',
        status: FavoriteStatus.ready,
        assets: [video, _asset()]);
    expect(favoriteThumbnailAsset(value)?.id, 'original-1');
    expect(
        favoriteThumbnailAsset(FavoriteItem(
            id: 'no-cover',
            version: 1,
            kind: FavoriteKind.video,
            title: '',
            status: FavoriteStatus.ready,
            assets: [video])),
        isNull);
  });

  testWidgets('list image shows decoded thumbnail and clears on account change',
      (tester) async {
    final original = (await tester.runAsync(
        () => File('${root.path}/thumbnail.png').writeAsBytes(_png)))!;
    final loader = _LocalLoader(original);
    await tester.runAsync(() async {
      await tester.pumpWidget(favoriteUiHost(Scaffold(
          body: SizedBox(
              width: 48,
              height: 48,
              child: FavoriteItemThumbnail(
                  repository: repository,
                  item: _item(),
                  loaderFactory: () => loader)))));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('favorite-thumbnail-fav-1')), findsOneWidget);
    expect(loader.closed, isTrue);
    repository.active = false;
    repository.notifyListeners();
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('voice list shows duration without requesting an audio original',
      (tester) async {
    final asset = FavoriteAsset(
        id: 'voice',
        mimeType: 'audio/mp4',
        sizeBytes: 10,
        sha256: '0' * 64,
        durationMs: 12500);
    final voice = FavoriteItem(
        id: 'voice-item',
        version: 1,
        kind: FavoriteKind.audio,
        title: '',
        status: FavoriteStatus.ready,
        assets: [asset]);
    await tester.pumpWidget(favoriteUiHost(
        Scaffold(
            body: SizedBox(
                width: 48,
                height: 48,
                child: FavoriteItemThumbnail(
                    repository: repository, item: voice))),
        dark: true));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(find.text('13″'), findsOneWidget);
    expect(headers, isEmpty);
    expect(repository.detailCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
