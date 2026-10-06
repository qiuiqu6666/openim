import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MediaCloud extends FavoriteApi {
  MediaCloud()
      : super(baseUrl: 'https://chat.test', tokenProvider: () => 'token');
  final initIDs = <String>[];
  final completeIDs = <String>[];
  final completedUploads = <String>[];
  final createIDs = <String>[];
  final createdAssets = <String>[];
  final sessions = <String, String>{};
  bool failInit = false;
  bool failComplete = false;
  bool failCreate = false;
  int uploads = 0;
  List<FavoriteItem> rows = [];
  @override
  Future<FavoriteQuota> getQuota({CancelToken? cancelToken}) async =>
      const FavoriteQuota(supportsFavorites: true, supportsPrepareSend: true);
  @override
  Future<FavoritePage> list(
          {String query = '',
          FavoriteKind? kind,
          String? tagID,
          String? cursor,
          int? baseline,
          int limit = 30,
          CancelToken? cancelToken}) async =>
      FavoritePage(items: rows, syncAt: 100);
  @override
  Future<FavoriteUploadSession> initializeUpload(
      {required String fileName,
      required String mimeType,
      required int sizeBytes,
      required String clientRequestID,
      CancelToken? cancelToken}) async {
    initIDs.add(clientRequestID);
    final id =
        sessions.putIfAbsent(clientRequestID, () => 'u${sessions.length + 1}');
    if (failInit) {
      failInit = false;
      throw const FavoriteApiException('NETWORK_ERROR', '初始化待确认',
          isUncertain: true);
    }
    return FavoriteUploadSession(
        uploadID: id,
        uploadURL: Uri.parse('https://storage.test/signed-$id'),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        maxSizeBytes: 100);
  }

  @override
  Future<void> uploadFile(FavoriteUploadSession session, File file,
      {CancelToken? cancelToken, ProgressCallback? onProgress}) async {
    uploads++;
  }

  @override
  Future<FavoriteAsset> completeUpload(String uploadID,
      {required String clientRequestID, CancelToken? cancelToken}) async {
    completeIDs.add(clientRequestID);
    completedUploads.add(uploadID);
    if (failComplete) {
      failComplete = false;
      throw const FavoriteApiException('NETWORK_ERROR', '上传完成待确认',
          isUncertain: true);
    }
    return FavoriteAsset(
        id: 'asset-$uploadID',
        mimeType: 'video/mp4',
        sizeBytes: 4,
        sha256: List.filled(64, 'a').join(),
        durationMs: 1500,
        coverAssetID: 'cover-$uploadID');
  }

  @override
  Future<FavoriteItem> create(
      {required FavoriteKind kind,
      required FavoriteContent content,
      required String clientRequestID,
      String title = '',
      List<String> uploadIDs = const [],
      List<String> assetIDs = const [],
      CancelToken? cancelToken}) async {
    createIDs.add(clientRequestID);
    createdAssets.add(content.blocks.single.assetID!);
    expect(content.blocks.single.data['coverAssetID'],
        'cover-${uploadIDs.single}');
    if (failCreate) {
      failCreate = false;
      throw const FavoriteApiException('NETWORK_ERROR', '创建待确认',
          isUncertain: true);
    }
    final item = FavoriteItem(
        id: 'saved',
        kind: kind,
        title: title,
        version: 1,
        status: FavoriteStatus.ready,
        content: content,
        contentRevision: 'r1');
    rows = [item];
    return item;
  }
}

class CleanupFault implements FavoriteMutationOutboxStore {
  final data = <String, String>{};
  bool denyComplete = true;
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<bool> write(String key, String value) async {
    final parsed = jsonDecode(value) as Map;
    if (denyComplete &&
        (parsed['confirmed'] as Map).isNotEmpty &&
        (parsed['pending'] as List).isEmpty) {
      return false;
    }
    data[key] = value;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File original;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory =
        await Directory.systemTemp.createTemp('favorite-media-recovery-');
    original = File('${directory.path}/original.mp4');
    await original.writeAsBytes([1, 2, 3, 4]);
  });
  tearDown(() async {
    if (await original.exists()) await original.delete();
    await directory.delete();
  });

  test('restart after an unknown upload init retains its exact UUID', () async {
    final api = MediaCloud()..failInit = true;
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(
        repo.createMedia(kind: FavoriteKind.video, filePath: original.path),
        throwsA(isA<FavoriteApiException>()));
    final restarted = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(restarted.dispose);
    await restarted.createMedia(
        kind: FavoriteKind.video, filePath: original.path);
    expect(api.initIDs, hasLength(2));
    expect(api.initIDs.first, api.initIDs.last);
    expect(api.sessions, hasLength(1));
    expect(api.createIDs, hasLength(1));
  });

  test(
      'lost complete receipt restarts with original upload and complete UUID without original bytes',
      () async {
    final api = MediaCloud()..failComplete = true;
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(
        repo.createMedia(kind: FavoriteKind.video, filePath: original.path),
        throwsA(isA<FavoriteApiException>()));
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${repo.accountNamespace}:metadata:v1')!;
    expect(raw, isNot(contains('https://storage.test')));
    await original.delete();
    final restarted = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(restarted.dispose);
    await restarted.createMedia(
        kind: FavoriteKind.video, filePath: original.path);
    expect(api.uploads, 1);
    expect(api.initIDs, hasLength(1));
    expect(api.completedUploads, ['u1', 'u1']);
    expect(api.completeIDs.first, api.completeIDs.last);
  });

  test(
      'replacing bytes at the same path obtains a fresh upload, asset and create UUID',
      () async {
    final api = MediaCloud()..failCreate = true;
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(
        repo.createMedia(kind: FavoriteKind.video, filePath: original.path),
        throwsA(isA<FavoriteApiException>()));
    await original.writeAsBytes([9, 8, 7, 6]);
    await repo.createMedia(kind: FavoriteKind.video, filePath: original.path);
    expect(api.uploads, 2);
    expect(api.sessions, hasLength(2));
    expect(api.initIDs.first, isNot(api.initIDs.last));
    expect(api.completeIDs.first, isNot(api.completeIDs.last));
    expect(api.createIDs.first, isNot(api.createIDs.last));
    expect(api.createdAssets, ['asset-u1', 'asset-u2']);
  });

  test(
      'confirmed outbox cleanup failure preserves final media and can retry without another upload',
      () async {
    final api = MediaCloud();
    final fault = CleanupFault();
    final repo = FavoriteRepository(
        api: api,
        userIDProvider: () => 'me',
        outbox: FavoriteMutationOutbox(store: fault));
    addTearDown(repo.dispose);
    await repo.createMedia(kind: FavoriteKind.video, filePath: original.path);
    expect(repo.pendingRecovery, hasLength(1));
    fault.denyComplete = false;
    await repo.createMedia(kind: FavoriteKind.video, filePath: original.path);
    expect(api.uploads, 1);
    expect(api.completeIDs, hasLength(1));
    expect(api.createdAssets, ['asset-u1', 'asset-u1']);
    expect(api.createIDs.first, api.createIDs.last);
    expect(repo.pendingRecovery, isEmpty);
  });
}
