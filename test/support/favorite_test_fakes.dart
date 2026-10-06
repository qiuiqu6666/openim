import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/services/favorite_message_builder.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

class FakeFavoriteFactory implements FavoriteMessageFactory {
  final List<Map<String, dynamic>> calls = [];
  int count = 0;
  Message _message(String method, int type, Map<String, dynamic> fields) {
    calls.add({'method': method, ...fields});
    return Message(
        clientMsgID: 'new-${++count}',
        contentType: type,
        status: MessageStatus.sending,
        textElem: method == 'text'
            ? TextElem(content: fields['text'] as String)
            : null);
  }

  @override
  Future<Message> text(String text) async =>
      _message('text', MessageType.text, {'text': text});
  @override
  Future<Message> image(String path) async =>
      _message('image', MessageType.picture, {'path': path});
  @override
  Future<Message> audio(String path, int durationSeconds) async => _message(
      'audio', MessageType.voice, {'path': path, 'duration': durationSeconds});
  @override
  Future<Message> video(String path, String mimeType, int durationSeconds,
          String snapshotPath) async =>
      _message('video', MessageType.video, {
        'path': path,
        'mime': mimeType,
        'duration': durationSeconds,
        'snapshot': snapshotPath
      });
  @override
  Future<Message> file(String path, String fileName) async =>
      _message('file', MessageType.file, {'path': path, 'fileName': fileName});
}

class FakeFavoriteDownloader implements FavoriteMediaDownloader {
  FakeFavoriteDownloader(this.bytes);
  final Map<String, List<int>> bytes;
  final List<String> downloaded = [];
  @override
  Future<void> download(FavoriteDownload grant, File destination,
      {required int maxBytes,
      required bool Function() isActive,
      void Function(int received, int total)? onProgress}) async {
    downloaded.add(grant.assetID);
    await destination.parent.create(recursive: true);
    final content = bytes[grant.assetID]!;
    await destination.writeAsBytes(content);
    onProgress?.call(content.length, grant.sizeBytes);
  }
}

class MemoryFavoriteTaskStore implements FavoriteSendTaskStore {
  final Map<String, List<Map<String, dynamic>>> values = {};
  @override
  Future<List<Map<String, dynamic>>> load(String namespace) async =>
      (values[namespace] ?? const [])
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
  @override
  Future<void> save(String namespace, List<Map<String, dynamic>> tasks) async {
    values[namespace] = tasks;
  }
}

class FakeFavoriteRepository extends FavoriteRepository {
  FakeFavoriteRepository(this.detail, {FavoritePreparedSend? prepared})
      : prepared = prepared ??
            favoritePrepared(detail.content!.blocks, kind: detail.kind),
        super(
            api: FavoriteApi(
                client: Dio(),
                baseUrl: 'https://business.example',
                tokenProvider: () => 'token'),
            userIDProvider: () => 'account',
            cacheEnabled: false);
  FavoriteItem detail;
  FavoritePreparedSend prepared;
  int prepareCalls = 0;
  final List<String> requestIDs = [];
  final List<String> attemptIDs = [];
  String owner = 'account';
  int sessionVersion = 0;
  bool favoritesAvailable = true;
  int capabilityChecks = 0;
  @override
  String get accountNamespace => 'business:$owner';
  @override
  String get sessionScope => '$accountNamespace:$sessionVersion';
  @override
  bool isSessionCurrent(String scope) => scope == sessionScope;
  @override
  Future<void> requireAvailable() async {
    capabilityChecks++;
    if (!favoritesAvailable) {
      throw const FavoriteApiException('FAVORITES_UNAVAILABLE', '收藏功能暂不可用');
    }
  }

  @override
  Future<FavoriteItem> getDetail(String id) async => detail;
  @override
  Future<FavoritePreparedSend> prepareForSend(String id,
      {required String expectedContentRevision,
      required String sendAttemptID,
      required String clientRequestID}) async {
    prepareCalls++;
    requestIDs.add(clientRequestID);
    attemptIDs.add(sendAttemptID);
    return prepared;
  }
}

FavoriteItem favoriteTextItem(
        {String id = 'private-favorite', List<FavoriteBlock>? blocks}) =>
    FavoriteItem(
        id: id,
        kind: FavoriteKind.note,
        title: 'private management title',
        version: 1,
        contentRevision: 'revision-1',
        status: FavoriteStatus.ready,
        content: FavoriteContent(
            kind: FavoriteKind.note,
            blocks: blocks ??
                const [FavoriteBlock(id: 'b1', type: 'text', text: 'hello')]),
        source: const FavoriteSource(
            conversationID: 'private-source', clientMsgID: 'old-id'));

FavoritePreparedSend favoritePrepared(List<FavoriteBlock> blocks,
        {FavoriteKind kind = FavoriteKind.note,
        List<FavoriteDownload> downloads = const [],
        DateTime? expiry}) =>
    FavoritePreparedSend(
        prepareID: 'prepare',
        contentRevision: 'revision-1',
        expiresAt: expiry ?? DateTime.now().add(const Duration(minutes: 10)),
        sendContent: FavoriteContent(kind: kind, blocks: blocks),
        downloads: downloads);

FavoriteAsset favoriteAsset(String id, List<int> bytes,
        {String mime = 'image/png',
        String role = 'original',
        int? durationMs,
        String? fileName}) =>
    FavoriteAsset(
        id: id,
        mimeType: mime,
        sizeBytes: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        role: role,
        durationMs: durationMs,
        fileName: fileName);
FavoriteDownload favoriteGrant(FavoriteAsset asset) => FavoriteDownload(
    assetID: asset.id,
    url: Uri.parse(
        'https://private-storage.example/${asset.id}?privateSignature=secret'),
    sizeBytes: asset.sizeBytes,
    sha256: asset.sha256);
