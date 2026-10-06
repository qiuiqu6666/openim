import 'dart:io';

import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

import 'favorite_models.dart';
import '../pages/favorites/models/favorite_quota.dart';
import '../pages/favorites/models/favorite_batch_delete.dart';
import '../pages/favorites/models/favorite_archive_retry.dart';

export 'favorite_models.dart';
export '../pages/favorites/models/favorite_quota.dart';
export '../pages/favorites/models/favorite_batch_delete.dart';
export '../pages/favorites/models/favorite_archive_retry.dart';

class FavoriteApiException implements Exception {
  const FavoriteApiException(this.code, this.message,
      {this.isUncertain = false, this.isCancelled = false, this.currentItem});
  final Object code;
  final String message;
  final bool isUncertain;
  final bool isCancelled;
  final FavoriteItem? currentItem;
  bool get isVersionConflict => code == 20061 || code == 'VERSION_CONFLICT';
  bool get isCursorExpired => code == 20064 || code == 'CURSOR_EXPIRED';
  bool get isRetryable => isUncertain || code == 20065 || code == 20066;
  bool get isAuthError =>
      code == 'AUTH_INVALID' ||
      code == 'AUTH_EXPIRED' ||
      code == 401 ||
      (code is int && (code as int) >= 1501 && (code as int) <= 1507);
  @override
  String toString() => message;
}

/// Uses the Chat identity. The IM token and authenticated Dio interceptors are
/// never forwarded to signed object-storage upload URLs.
class FavoriteApi {
  FavoriteApi(
      {Dio? client,
      Dio? uploadClient,
      String? baseUrl,
      String? Function()? tokenProvider})
      : _client = client ?? dio,
        _uploadClient = uploadClient ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 5))),
        _baseUrl = baseUrl,
        _tokenProvider = tokenProvider ?? (() => DataSp.chatToken);

  final Dio _client;
  final Dio _uploadClient;
  final String? _baseUrl;
  final String? Function() _tokenProvider;
  String get baseUrl =>
      (_baseUrl ?? Config.appAuthUrl).replaceFirst(RegExp(r'/+$'), '');
  String? get sessionToken => _tokenProvider();
  static String newRequestID() => const Uuid().v4();

  static void _id(String value) {
    if (value.trim().isEmpty ||
        value.length > 512 ||
        value.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError('Invalid favorite identifier');
    }
  }

  static void _requestID(String value) {
    if (!RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(value)) {
      throw ArgumentError('Invalid favorite request identifier');
    }
  }

  String _itemPath(String id) {
    _id(id);
    return '/chat/favorites/${Uri.encodeComponent(id)}';
  }

  bool _isLoopback(Uri uri) {
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    return host == 'localhost' ||
        (InternetAddress.tryParse(host)?.isLoopback ?? false);
  }

  void _validateMediaEndpoint(Uri grantURL) {
    final service = Uri.tryParse(baseUrl);
    if (service != null &&
        service.host.isNotEmpty &&
        !_isLoopback(service) &&
        _isLoopback(grantURL)) {
      // A signed loopback URL points to the user's device. Its signed host must
      // be corrected by the service, never rewritten by the client.
      throw const FavoriteApiException(
          'MEDIA_ENDPOINT_UNREACHABLE', '媒体地址配置错误，请联系管理员修正收藏存储地址');
    }
  }

  Future<Map<String, dynamic>> _request(String path,
      {String method = 'GET',
      Map<String, dynamic>? data,
      Map<String, dynamic>? query,
      CancelToken? cancelToken,
      bool mutation = false,
      Set<int> acceptedCodes = const {}}) async {
    final token = sessionToken;
    if (token == null || token.isEmpty) {
      throw const FavoriteApiException('AUTH_INVALID', '请先登录');
    }
    Response<dynamic> response;
    try {
      response = await _client.request<dynamic>('$baseUrl$path',
          data: data,
          queryParameters: query,
          cancelToken: cancelToken,
          options: Options(
              method: method,
              headers: {'token': token, 'operationID': newRequestID()},
              contentType: data == null ? null : Headers.jsonContentType));
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const FavoriteApiException('CANCELLED', '操作已取消',
            isCancelled: true);
      }
      if (error.response?.data is Map) {
        final body = favoriteJsonMap(error.response!.data);
        if (body['errCode'] is int && body['errCode'] != 0) {
          if (acceptedCodes.contains(body['errCode'])) {
            return favoriteJsonMap(body['data']);
          }
          throw _businessError(body);
        }
      }
      if (error.response?.statusCode == 401) {
        throw const FavoriteApiException('AUTH_EXPIRED', '登录已失效，请重新登录');
      }
      throw FavoriteApiException('NETWORK_ERROR', '收藏服务暂不可用，请稍后重试',
          isUncertain: mutation && error.response == null);
    }
    final body = favoriteJsonMap(response.data);
    if (body['errCode'] is! int) {
      throw const FormatException('Invalid favorites response');
    }
    if (body['errCode'] != 0 && !acceptedCodes.contains(body['errCode'])) {
      throw _businessError(body);
    }
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw const FavoriteApiException('HTTP_ERROR', '收藏服务暂不可用，请稍后重试');
    }
    // Successful void operations may omit data. DTO callers still validate the
    // resulting object and cannot manufacture missing items or pages.
    return favoriteJsonMap(body['data'] ?? <String, dynamic>{});
  }

  FavoriteApiException _businessError(Map<String, dynamic> body) {
    final code = body['errCode'] as int;
    const messages = {
      1001: '收藏参数不正确，请检查后重试',
      20050: '收藏不存在或无法访问',
      20051: '该内容已经收藏',
      20052: '无法访问原消息',
      20053: '原消息已经撤回',
      20054: '暂不支持此类收藏',
      20055: '该内容不能收藏或发送',
      20056: '收藏原件不可用',
      20057: '当前状态不能重试归档',
      20058: '文件超过大小限制',
      20059: '文件格式或内容不支持',
      20060: '收藏空间已满，请清理后重试',
      20061: '收藏已在其他设备修改，请刷新后重试',
      20062: '本次请求内容已变化，请重新操作',
      20063: '发送准备已过期，请重新准备',
      20064: '收藏同步记录已过期，正在重新同步',
      20065: '操作过于频繁，请稍后重试',
      20066: '收藏服务暂不可用，请稍后重试',
      20067: '本次请求对应的收藏已经删除',
    };
    if (code >= 1501 && code <= 1507) {
      return FavoriteApiException(code, '登录已失效，请重新登录');
    }
    // Never expose a server error detail, token, private URL or body in a toast.
    FavoriteItem? current;
    if (code == 20061 && body['data'] is Map) {
      final data = favoriteJsonMap(body['data']);
      if (data['item'] is Map) {
        try {
          current = FavoriteItem.fromJson(favoriteJsonMap(data['item']));
        } on FormatException {
          /* A malformed hint never replaces local editing. */
        }
      }
    }
    return FavoriteApiException(code, messages[code] ?? '收藏操作失败，请稍后重试',
        currentItem: current);
  }

  Future<FavoriteQuota> getQuota({CancelToken? cancelToken}) async =>
      FavoriteQuota.fromJson(
          await _request('/chat/favorites/quota', cancelToken: cancelToken));

  FavoriteItem _item(Map<String, dynamic> data) =>
      FavoriteItem.fromJson(favoriteJsonMap(data['item'] ?? data));

  Future<FavoritePage> list(
      {String query = '',
      FavoriteKind? kind,
      String? tagID,
      String? cursor,
      int? baseline,
      int limit = 30,
      CancelToken? cancelToken}) async {
    if (limit < 1 ||
        limit > 100 ||
        query.runes.length > 64 ||
        (kind != null && !kind.isP0) ||
        (cursor != null && baseline == null) ||
        (baseline != null && baseline < 0)) {
      throw ArgumentError('Invalid favorites filter');
    }
    if (tagID != null) {
      throw const FavoriteApiException('UNSUPPORTED_CONTENT', '标签功能暂未开放');
    }
    final page = FavoritePage.fromJson(await _request('/chat/favorites',
        query: {
          'limit': limit,
          if (query.isNotEmpty) 'q': query,
          if (kind != null) 'kind': kind.wireName,
          if (cursor != null) 'cursor': cursor,
          if (baseline != null) 'baseline': baseline
        },
        cancelToken: cancelToken));
    if (cursor != null && page.nextCursor == cursor) {
      throw const FormatException('Favorites cursor did not advance');
    }
    if (baseline != null && page.syncAt != baseline) {
      throw const FormatException('Favorite list baseline mismatch');
    }
    return page;
  }

  Future<FavoriteItem> getDetail(String id, {CancelToken? cancelToken}) async {
    final data = await _request(_itemPath(id), cancelToken: cancelToken);
    final item = FavoriteItem.fromJson(favoriteJsonMap(data['item']));
    if (item.id != id) throw const FormatException('Favorite ID mismatch');
    return item;
  }

  Future<FavoriteItem> createFromMessage(
      {required FavoriteSource source,
      required String clientRequestID,
      CancelToken? cancelToken}) async {
    _requestID(clientRequestID);
    if (source.conversationID == null ||
        source.conversationID!.isEmpty ||
        source.clientMsgID == null ||
        source.clientMsgID!.isEmpty ||
        source.sequence == null ||
        source.sequence! <= 0) {
      throw ArgumentError('Missing favorite source locator');
    }
    final locator = {
      'conversationID': source.conversationID,
      'clientMsgID': source.clientMsgID,
      'sequence': source.sequence
    };
    return _item(await _request('/chat/favorites',
        method: 'POST',
        data: {
          'clientRequestID': clientRequestID,
          'origin': 'message',
          'source': locator
        },
        mutation: true,
        acceptedCodes: const {20051},
        cancelToken: cancelToken));
  }

  Future<FavoriteItem> create(
      {required FavoriteKind kind,
      required FavoriteContent content,
      required String clientRequestID,
      String title = '',
      List<String> uploadIDs = const [],
      List<String> assetIDs = const [],
      CancelToken? cancelToken}) async {
    _requestID(clientRequestID);
    if (!kind.isP0 || kind == FavoriteKind.text || content.kind != kind) {
      throw ArgumentError('Invalid favorite content kind');
    }
    return _item(await _request('/chat/favorites',
        method: 'POST',
        mutation: true,
        cancelToken: cancelToken,
        data: {
          'clientRequestID': clientRequestID,
          'origin': 'userCreated',
          'kind': kind.wireName,
          'title': title,
          'content': {
            'blocks': content.blocks.map((block) => block.toJson()).toList()
          },
          if (uploadIDs.isNotEmpty) 'uploadIDs': uploadIDs,
          if (assetIDs.isNotEmpty) 'assetIDs': assetIDs
        }));
  }

  Future<FavoriteItem> update(String id,
      {required int expectedVersion,
      required String clientRequestID,
      String? title,
      FavoriteContent? content,
      List<String>? tagIDs,
      CancelToken? cancelToken}) async {
    _requestID(clientRequestID);
    if (expectedVersion < 1) throw ArgumentError('Invalid favorite version');
    if (tagIDs != null) {
      throw const FavoriteApiException('UNSUPPORTED_CONTENT', '标签功能暂未开放');
    }
    final item = _item(await _request(_itemPath(id),
        method: 'PATCH',
        mutation: true,
        cancelToken: cancelToken,
        data: {
          'clientRequestID': clientRequestID,
          'expectedVersion': expectedVersion,
          if (title != null) 'title': title,
          if (content != null)
            'content': {
              'blocks': content.blocks.map((block) => block.toJson()).toList()
            },
        }));
    if (item.id != id) throw const FormatException('Favorite ID mismatch');
    return item;
  }

  Future<FavoriteBatchDeleteResult> batchDelete(List<FavoriteItem> items,
      {required String clientRequestID, CancelToken? cancelToken}) async {
    _requestID(clientRequestID);
    if (items.isEmpty ||
        items.length > 100 ||
        items.map((item) => item.id).toSet().length != items.length ||
        items.any((item) => item.version < 1)) {
      throw ArgumentError('Invalid favorite delete batch');
    }
    final result = FavoriteBatchDeleteResult.fromJson(await _request(
        '/chat/favorites/batch-delete',
        method: 'POST',
        mutation: true,
        cancelToken: cancelToken,
        data: {
          'clientRequestID': clientRequestID,
          'items': items
              .map((item) => {'id': item.id, 'expectedVersion': item.version})
              .toList()
        }));
    if (result.items.length != items.length ||
        !result.items
            .every((item) => items.any((sent) => sent.id == item.id))) {
      throw const FormatException('Favorite delete batch mismatch');
    }
    return result;
  }

  Future<void> delete(String id,
      {required int expectedVersion,
      required String clientRequestID,
      CancelToken? cancelToken}) async {
    _requestID(clientRequestID);
    if (expectedVersion < 1) throw ArgumentError('Invalid favorite version');
    await _request(_itemPath(id),
        method: 'DELETE',
        mutation: true,
        cancelToken: cancelToken,
        query: {
          'clientRequestID': clientRequestID,
          'expectedVersion': expectedVersion
        });
  }

  Future<FavoritePreparedSend> prepareForSend(String id,
      {required String expectedContentRevision,
      required String sendAttemptID,
      required String clientRequestID,
      CancelToken? cancelToken}) async {
    _requestID(clientRequestID);
    _requestID(sendAttemptID);
    _id(expectedContentRevision);
    final prepared = FavoritePreparedSend.fromJson(await _request(
        '${_itemPath(id)}/prepare-send',
        method: 'POST',
        mutation: true,
        cancelToken: cancelToken,
        data: {
          'clientRequestID': clientRequestID,
          'sendAttemptID': sendAttemptID,
          'expectedContentRevision': expectedContentRevision
        }));
    if (prepared.contentRevision != expectedContentRevision) {
      throw const FormatException('Prepared favorite revision mismatch');
    }
    for (final download in prepared.downloads) {
      _validateMediaEndpoint(download.url);
    }
    return prepared;
  }

  Future<FavoriteDownload> assetAccess(String id, String assetID,
      {CancelToken? cancelToken}) async {
    _id(assetID);
    final data = await _request('${_itemPath(id)}/asset-access',
        method: 'POST', cancelToken: cancelToken, data: {'assetID': assetID});
    final payload = favoriteJsonMap(data['download'] ?? data);
    payload.putIfAbsent('assetID', () => assetID);
    final download = FavoriteDownload.fromJson(payload);
    if (download.assetID != assetID) {
      throw const FormatException('Favorite asset mismatch');
    }
    if (download.expiresAt == null) {
      throw const FormatException(
          'Missing favorite asset authorization expiry');
    }
    _validateMediaEndpoint(download.url);
    return download;
  }

  Future<FavoriteArchiveRetryAck> retryArchive(String id,
      {required String clientRequestID, CancelToken? cancelToken}) async {
    _requestID(clientRequestID);
    return FavoriteArchiveRetryAck.fromJson(await _request(
        '${_itemPath(id)}/retry-archive',
        method: 'POST',
        mutation: true,
        cancelToken: cancelToken,
        data: {'clientRequestID': clientRequestID}));
  }

  Future<FavoriteChangesPage> changes(
      {required int updatedAfter,
      int limit = 100,
      CancelToken? cancelToken}) async {
    if (limit < 1 || limit > 100 || updatedAfter < 0) {
      throw ArgumentError('Invalid favorite changes limit');
    }
    final page = FavoriteChangesPage.fromJson(
        await _request('/chat/favorites/changes',
            cancelToken: cancelToken,
            query: {'limit': limit, 'updatedAfter': updatedAfter}),
        limit: limit);
    if (page.syncAt < updatedAfter ||
        (page.hasMore && page.syncAt <= updatedAfter)) {
      throw const FormatException('Favorite changes watermark did not advance');
    }
    return page;
  }

  Future<List<FavoriteTag>> listTags({CancelToken? cancelToken}) async {
    throw const FavoriteApiException('UNSUPPORTED_CONTENT', '标签功能暂未开放');
  }

  Future<FavoriteTag> createTag(String name,
      {required String clientRequestID, CancelToken? cancelToken}) async {
    throw const FavoriteApiException('UNSUPPORTED_CONTENT', '标签功能暂未开放');
  }

  Future<FavoriteTag> updateTag(String id, String name,
      {required int expectedVersion,
      required String clientRequestID,
      CancelToken? cancelToken}) async {
    throw const FavoriteApiException('UNSUPPORTED_CONTENT', '标签功能暂未开放');
  }

  Future<void> deleteTag(String id,
      {required int expectedVersion,
      required String clientRequestID,
      CancelToken? cancelToken}) async {
    throw const FavoriteApiException('UNSUPPORTED_CONTENT', '标签功能暂未开放');
  }

  Future<FavoriteUploadSession> initializeUpload(
      {required String fileName,
      required String mimeType,
      required int sizeBytes,
      required String clientRequestID,
      CancelToken? cancelToken}) async {
    _requestID(clientRequestID);
    if (fileName.isEmpty || sizeBytes <= 0) {
      throw ArgumentError('Empty favorite upload');
    }
    final session = FavoriteUploadSession.fromJson(
        await _request('/chat/favorites/uploads',
            method: 'POST',
            mutation: true,
            cancelToken: cancelToken,
            data: {
              'clientRequestID': clientRequestID,
              'fileName': fileName,
              'declaredMimeType': mimeType,
              'declaredSizeBytes': sizeBytes,
              'purpose': 'favorite_original'
            }),
        declaredMimeType: mimeType);
    _validateMediaEndpoint(session.uploadURL);
    return session;
  }

  Future<void> uploadFile(FavoriteUploadSession session, File file,
      {CancelToken? cancelToken, ProgressCallback? onProgress}) async {
    if (session.method != 'PUT') {
      throw const FormatException('Invalid favorite upload method');
    }
    final size = await file.length();
    if (size > session.maxSizeBytes || size <= 0) {
      throw const FavoriteApiException('MEDIA_TOO_LARGE', '文件超过大小限制');
    }
    if (session.expiresAt.isBefore(DateTime.now().toUtc())) {
      throw const FavoriteApiException('UPLOAD_EXPIRED', '上传授权已过期，请重试');
    }
    final headers = Map<String, dynamic>.from(session.headers);
    if (headers.keys.any((key) =>
        {'token', 'authorization', 'cookie'}.contains(key.toLowerCase()))) {
      throw const FormatException('Invalid favorite upload authorization');
    }
    final signedContentTypes = headers.entries
        .where((entry) => entry.key.toLowerCase() == Headers.contentTypeHeader);
    final contentType = signedContentTypes.isEmpty
        ? session.contentType ?? 'application/octet-stream'
        : signedContentTypes.first.value.toString();
    if (contentType.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Invalid favorite upload content type');
    }
    headers[Headers.contentLengthHeader] = size;
    try {
      await _uploadClient.request<dynamic>(session.uploadURL.toString(),
          data: file.openRead(),
          cancelToken: cancelToken,
          onSendProgress: onProgress,
          options: Options(
              method: 'PUT',
              headers: headers,
              followRedirects: false,
              contentType: contentType));
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const FavoriteApiException('CANCELLED', '操作已取消',
            isCancelled: true);
      }
      throw const FavoriteApiException('UPLOAD_FAILED', '原件上传失败，请重试',
          isUncertain: true);
    }
  }

  Future<FavoriteAsset> completeUpload(String uploadID,
      {required String clientRequestID, CancelToken? cancelToken}) async {
    _id(uploadID);
    _requestID(clientRequestID);
    final data = await _request(
        '/chat/favorites/uploads/${Uri.encodeComponent(uploadID)}/complete',
        method: 'POST',
        mutation: true,
        cancelToken: cancelToken,
        data: {'clientRequestID': clientRequestID});
    return FavoriteAsset.fromJson(favoriteJsonMap(data['asset'] ?? data));
  }
}
