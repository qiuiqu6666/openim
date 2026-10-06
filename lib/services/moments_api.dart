import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

import 'moments_models.dart';
export 'moments_models.dart';

/// Uses the business chatToken. IM tokens are never sent to business endpoints.
class MomentsApi {
  MomentsApi({Dio? client, String? baseUrl, String? Function()? tokenProvider})
      : _client = client ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30))),
        _baseUrl = baseUrl,
        _tokenProvider = tokenProvider;
  final Dio _client;
  final String? _baseUrl;
  final String? Function()? _tokenProvider;
  String get baseUrl =>
      (_baseUrl ?? Config.appAuthUrl).replaceFirst(RegExp(r'/+$'), '');
  String? get _token =>
      _tokenProvider != null ? _tokenProvider() : DataSp.chatToken;
  Map<String, String> get mediaHeaders {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw const MomentsException('请重新登录',
          code: 'AUTH_REQUIRED', authRequired: true);
    }
    return {'token': token};
  }

  Future<MomentsCapabilities> capabilities() async =>
      MomentsCapabilities.fromJson(await _request('/moments/capabilities'));
  Future<MomentsPageResult<MomentPost>> feed(
          {String? cursor, int pageSize = 20}) async =>
      MomentsPageResult.fromJson(
          await _request('/moments/feed', query: _pageQuery(cursor, pageSize)),
          MomentPost.fromJson);
  Future<MomentsPageResult<MomentPost>> userMoments(String userId,
          {String? cursor, int pageSize = 20}) async =>
      MomentsPageResult.fromJson(
          await _request('/moments/users/${_id(userId)}',
              query: _pageQuery(cursor, pageSize)),
          MomentPost.fromJson);
  Future<MomentPost> detail(String momentId) async =>
      _post(await _request('/moments/${_id(momentId)}'));
  Future<MomentsPageResult<MomentComment>> comments(String momentId,
          {String? cursor, int pageSize = 20}) async =>
      MomentsPageResult.fromJson(
          await _request('/moments/${_id(momentId)}/comments',
              query: _pageQuery(cursor, pageSize)),
          MomentComment.fromJson);
  Future<MomentsPageResult<MomentLike>> likes(String momentId,
          {String? cursor, int pageSize = 20}) async =>
      MomentsPageResult.fromJson(
          await _request('/moments/${_id(momentId)}/likes',
              query: _pageQuery(cursor, pageSize)),
          MomentLike.fromJson);

  Future<MomentPost> createPost(
      {required String clientRequestID,
      String text = '',
      List<String> mediaIds = const [],
      String visibility = 'FRIENDS',
      List<String> audienceUserIds = const []}) async {
    _id(clientRequestID);
    _validateAudience(visibility, audienceUserIds);
    if (text.trim().isEmpty && mediaIds.isEmpty) {
      throw const MomentsException('请填写文字或选择图片');
    }
    if (text.trim().runes.length > 2000 || mediaIds.length > 9) {
      throw const MomentsException('发布内容超过限制');
    }
    for (final id in mediaIds) {
      _id(id);
    }
    final data = await _request('/moments',
        method: 'POST',
        mutation: true,
        idempotencyKey: clientRequestID,
        data: {
          'clientRequestID': clientRequestID,
          'text': text.trim(),
          'mediaIDs': mediaIds,
          'visibility': visibility,
          'audienceUserIds': audienceUserIds,
        });
    try {
      return _post(data);
    } catch (_) {
      // Creation may be committed even if its acknowledgement cannot be decoded.
      throw const MomentsException('发布结果尚未确认',
          code: 'UNKNOWN_RESULT', unknownResult: true);
    }
  }

  Future<MomentsWriteResult> queryPublishResult(String clientRequestID) async =>
      MomentsWriteResult.fromJson(
          await _request('/moments/publish-results/${_id(clientRequestID)}'));
  Future<MomentsWriteResult> queryCommentResult(String clientRequestID) async =>
      MomentsWriteResult.fromJson(
          await _request('/moments/comment-results/${_id(clientRequestID)}'));
  Future<void> deletePost(String momentId) async {
    await _request('/moments/${_id(momentId)}',
        method: 'DELETE', mutation: true);
  }

  Future<void> setLiked(String momentId, bool liked) async {
    await _request('/moments/${_id(momentId)}/likes${liked ? '' : '/me'}',
        method: liked ? 'POST' : 'DELETE', mutation: true);
  }

  Future<MomentComment> createComment(String momentId,
      {required String text,
      required String clientRequestId,
      String? replyToCommentId}) async {
    _id(clientRequestId);
    if (text.trim().isEmpty || text.trim().runes.length > 500) {
      throw const MomentsException('评论需为 1～500 个字');
    }
    if (replyToCommentId != null && replyToCommentId.isNotEmpty) {
      _id(replyToCommentId);
    }
    final data = await _request('/moments/${_id(momentId)}/comments',
        method: 'POST',
        mutation: true,
        idempotencyKey: clientRequestId,
        data: {
          'clientRequestID': clientRequestId,
          'text': text.trim(),
          'replyToCommentID': replyToCommentId ?? ''
        });
    try {
      return MomentComment.fromJson(momentsMap(data['comment'] ?? data));
    } catch (_) {
      throw const MomentsException('评论结果尚未确认',
          code: 'UNKNOWN_RESULT', unknownResult: true);
    }
  }

  Future<void> deleteComment(String momentId, String commentId) async {
    await _request('/moments/${_id(momentId)}/comments/${_id(commentId)}',
        method: 'DELETE', mutation: true);
  }

  Future<MomentPost> updateVisibility(String momentId,
      {required String visibility,
      List<String> audienceUserIds = const [],
      required int expectedVersion}) async {
    _validateAudience(visibility, audienceUserIds);
    return _post(await _request('/moments/${_id(momentId)}/visibility',
        method: 'PATCH',
        mutation: true,
        data: {
          'visibility': visibility,
          'audienceUserIds': audienceUserIds,
          'expectedVersion': expectedVersion
        }));
  }

  Future<void> reportPost(String momentId,
      {required String reason, String? commentId}) async {
    throw const MomentsException('当前朋友圈暂未开放举报',
        code: 'REPORTS_UNSUPPORTED', unavailable: true);
  }

  Future<MomentMedia> uploadMedia(
      {required String filePath,
      required String clientMediaId,
      String type = 'IMAGE',
      String? fileName,
      ProgressCallback? onProgress,
      CancelToken? cancelToken}) async {
    _id(clientMediaId);
    final token = _requireToken();
    final base = baseUrl;
    if (type != 'IMAGE') {
      throw const MomentsException('当前仅支持图片', code: 'MEDIA_TYPE_UNSUPPORTED');
    }
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      'clientMediaId': clientMediaId
    });
    _checkSession(token, base);
    return MomentMedia.fromJson(await _request('/moments/media/upload',
        method: 'POST',
        mutation: true,
        data: form,
        onProgress: onProgress,
        cancelToken: cancelToken));
  }

  Future<MomentMedia> uploadCover(
      {required String filePath,
      required String clientMediaId,
      String? fileName,
      ProgressCallback? onProgress,
      CancelToken? cancelToken}) async {
    _id(clientMediaId);
    final token = _requireToken();
    final base = baseUrl;
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      'clientMediaId': clientMediaId,
    });
    _checkSession(token, base);
    return MomentMedia.fromJson(await _request('/moments/cover/upload',
        method: 'POST',
        mutation: true,
        data: form,
        onProgress: onProgress,
        cancelToken: cancelToken));
  }

  /// Kept for source compatibility. The deployed contract has no status route.
  /// Retry upload with its original clientMediaId to confirm the same media.
  Future<MomentMedia> mediaStatus(String mediaId) async {
    throw const MomentsException('请重试原上传任务确认图片状态',
        code: 'MEDIA_STATUS_UNSUPPORTED', unavailable: true);
  }

  /// Only the business service's media proxy may receive the chatToken.
  String mediaUrl(String path) {
    final base = Uri.parse(baseUrl);
    final supplied = Uri.tryParse(path);
    if (supplied == null ||
        path.isEmpty ||
        supplied.userInfo.isNotEmpty ||
        path.startsWith('//') ||
        supplied.queryParameters.keys
            .any((key) => key.toLowerCase().contains('token'))) {
      throw const MomentsException('媒体访问地址不符合授权协议', code: 'MEDIA_URL_INVALID');
    }
    final uri = supplied.hasScheme
        ? supplied
        : Uri.parse('$baseUrl/${path.replaceFirst(RegExp(r'^/+'), '')}');
    final prefix = '${base.path.replaceFirst(RegExp(r'/+$'), '')}/moments/';
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.origin != base.origin ||
        !uri.path.startsWith(prefix) ||
        uri.pathSegments.any((part) => part == '..')) {
      throw const MomentsException('无法安全读取该媒体', code: 'MEDIA_URL_INVALID');
    }
    return uri.toString();
  }

  Future<Uint8List> downloadMedia(MomentMedia media,
      {bool thumbnail = false}) async {
    final path = thumbnail && media.thumbPath.isNotEmpty
        ? media.thumbPath
        : media.contentPath.isNotEmpty
            ? media.contentPath
            : '/moments/media/${_id(media.mediaId)}/content${thumbnail ? '?variant=thumb' : ''}';
    final url = mediaUrl(path);
    final token = _requireToken();
    final base = baseUrl;
    try {
      final response = await _client.get<List<int>>(url,
          options: Options(
              headers: {'token': token, 'operationID': const Uuid().v4()},
              responseType: ResponseType.bytes,
              followRedirects: false,
              validateStatus: (_) => true));
      _checkSession(token, base);
      _checkStatus(response.statusCode, false, null);
      if (response.data == null) throw const MomentsException('媒体内容不可用');
      return Uint8List.fromList(response.data!);
    } on DioException {
      _checkSession(token, base);
      throw const MomentsException('媒体加载失败，请稍后重试');
    }
  }

  Future<MomentsSettings> settings() async =>
      MomentsSettings.fromJson(await _request('/moments/settings'));
  Future<MomentsSettings> updateSettings(
      {int? visibleRangeDays,
      String? coverMediaId,
      bool clearCover = false,
      required int expectedVersion}) async {
    if (visibleRangeDays != null &&
        !const [0, 3, 90, 180, 365].contains(visibleRangeDays)) {
      throw const MomentsException('请选择有效的时间范围');
    }
    return MomentsSettings.fromJson(await _request('/moments/settings',
        method: 'PATCH',
        mutation: true,
        data: {
          'expectedVersion': expectedVersion,
          if (visibleRangeDays != null) 'visibleRangeDays': visibleRangeDays,
          if (clearCover || coverMediaId != null)
            'coverMediaId': clearCover ? null : coverMediaId
        }));
  }

  /// A command acknowledgement, with a legacy return type for callers/fakes.
  /// An empty/minimal response does not describe global settings or list state.
  Future<MomentsSettings> setBlockedViewer(String userId, bool blocked) async =>
      MomentsSettings.fromJson(await _request(
          '/moments/settings/blocked-viewers/${_id(userId)}',
          method: blocked ? 'PUT' : 'DELETE',
          mutation: true));

  /// Await success to confirm this one operation; do not apply this return
  /// value over cached global settings or infer a full server-side list.
  Future<MomentsSettings> setHiddenAuthor(String userId, bool hidden) async =>
      MomentsSettings.fromJson(await _request(
          '/moments/settings/hidden-authors/${_id(userId)}',
          method: hidden ? 'PUT' : 'DELETE',
          mutation: true));
  Future<MomentsPageResult<MomentNotification>> notifications(
          {String? cursor, int pageSize = 20}) async =>
      MomentsPageResult.fromJson(
          await _request('/moments/notifications',
              query: _pageQuery(cursor, pageSize)),
          MomentNotification.fromJson);
  Future<int> markNotificationsRead(
      {List<String> notificationIds = const [],
      int? readThroughSeq,
      String? seenWatermark}) async {
    if (readThroughSeq != null &&
        (seenWatermark == null || seenWatermark.isEmpty)) {
      throw const MomentsException('请刷新消息列表后再标记已读');
    }
    final data = await _request('/moments/notifications/read',
        method: 'POST',
        mutation: true,
        data: {
          'notificationIDs': notificationIds,
          'markThrough': readThroughSeq != null,
          if (readThroughSeq != null) 'readThroughSeq': readThroughSeq,
          if (seenWatermark != null) 'seenWatermark': seenWatermark
        });
    final count = data['unreadCount'];
    if (count is! num || count < 0) {
      throw const FormatException('Missing unread count');
    }
    return count.toInt();
  }

  Future<Map<String, dynamic>> sync(List<String> momentIds) async {
    if (momentIds.length > 50 ||
        momentIds.any((id) => id.trim().isEmpty || id != id.trim())) {
      throw const MomentsException('每次同步最多 50 个有效动态 ID，请分批同步',
          code: 'ArgsError');
    }
    return _request('/moments/sync',
        method: 'POST', data: {'momentIDs': List<String>.of(momentIds)});
  }

  Future<Map<String, dynamic>> _request(String path,
      {String method = 'GET',
      dynamic data,
      Map<String, dynamic>? query,
      bool mutation = false,
      String? idempotencyKey,
      ProgressCallback? onProgress,
      CancelToken? cancelToken}) async {
    final token = _requireToken();
    final base = baseUrl;
    Response<dynamic> response;
    try {
      response = await _client.request<dynamic>('$base$path',
          data: data,
          queryParameters: query,
          cancelToken: cancelToken,
          onSendProgress: onProgress,
          options: Options(
              method: method,
              headers: {
                'token': token,
                'operationID': const Uuid().v4(),
                if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey
              },
              contentType: data is FormData ? null : Headers.jsonContentType,
              followRedirects: false,
              validateStatus: (_) => true));
    } on DioException catch (error) {
      _checkSession(token, base, mutation: mutation);
      if (error.response != null) {
        _checkStatus(
            error.response?.statusCode, mutation, error.response?.data);
      }
      throw MomentsException('请求失败，请稍后重试',
          code: 'NETWORK_ERROR', unknownResult: mutation);
    }
    _checkSession(token, base, mutation: mutation);
    _checkStatus(response.statusCode, mutation, response.data);
    final body = response.data;
    if (body is! Map || body['errCode'] is! int) {
      throw MomentsException('服务端响应不符合朋友圈协议',
          code: 'INVALID_RESPONSE', unknownResult: mutation);
    }
    if (body['errCode'] != 0) {
      _throwBusinessError(body);
    }
    if (body['data'] == null && mutation) return {};
    if (body['data'] is! Map) {
      throw MomentsException('服务端响应不符合朋友圈协议',
          code: 'INVALID_RESPONSE', unknownResult: mutation);
    }
    return Map<String, dynamic>.from(body['data']);
  }

  String _requireToken() {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw const MomentsException('请重新登录',
          code: 'AUTH_REQUIRED', authRequired: true);
    }
    return token;
  }

  void _checkSession(String token, String base, {bool mutation = false}) {
    if (_token != token || baseUrl != base) {
      throw MomentsException('登录状态已变化',
          code: 'SESSION_CHANGED', authRequired: true, unknownResult: mutation);
    }
  }

  void _checkStatus(int? status, bool mutation, dynamic body) {
    if (status != null && status >= 200 && status < 300) return;
    // Only explicit known business rejections override transport status.
    // Unknown 5xx responses still leave a write's commit state uncertain.
    if (body is Map &&
        body['errCode'] is int &&
        (body['errCode'] == 1001 ||
            body['errCode'] == 20012 &&
                const {
                  'MOMENT_UNAVAILABLE',
                  'PERMISSION_REVOKED',
                  'RELATION_UNAVAILABLE',
                  'IDEMPOTENCY_CONFLICT',
                  'VERSION_CONFLICT',
                  'MEDIA_NOT_READY',
                  'MEDIA_EXPIRED',
                  'CURSOR_EXPIRED',
                  'CONTEXT_CHANGED'
                }.contains(body['errDlt']))) {
      _throwBusinessError(body);
    }
    if (status == 404 || status == 501) {
      throw MomentsException('朋友圈服务尚未开放或资源不可用',
          statusCode: status, code: 'UNAVAILABLE', unavailable: true);
    }
    if (status == 401) {
      throw MomentsException('请重新登录',
          statusCode: status, code: 'AUTH_REQUIRED', authRequired: true);
    }
    if (status == 403 || status == 410) {
      throw MomentsException('内容已不可用或无权查看',
          statusCode: status,
          code: 'PERMISSION_REVOKED',
          permissionDenied: true);
    }
    throw MomentsException('请求失败，请稍后重试',
        statusCode: status,
        code: 'HTTP_ERROR',
        unknownResult: mutation && (status == null || status >= 500));
  }

  Never _throwBusinessError(Map body) {
    final errCode = body['errCode'];
    final semantic = errCode == 20012
        ? body['errDlt']
        : errCode == 1001
            ? 'ArgsError'
            : body['errDlt'] ?? body['errorCode'] ?? body['errMsg'];
    final code =
        semantic is String && semantic.isNotEmpty ? semantic : '$errCode';
    final relationUnavailable = code == 'RELATION_UNAVAILABLE';
    throw MomentsException(
        body['errMsg'] is String && (body['errMsg'] as String).isNotEmpty
            ? body['errMsg']
            : '操作未完成，请稍后重试',
        code: code,
        relationUnavailable: relationUnavailable,
        unavailable: !relationUnavailable &&
            (code.contains('UNAVAILABLE') &&
                    !code.contains('MOMENT_UNAVAILABLE') ||
                code.contains('NOT_IMPLEMENTED')),
        permissionDenied: code.contains('FORBIDDEN') ||
            code.contains('REVOKED') ||
            code == 'MOMENT_UNAVAILABLE',
        authRequired:
            code.contains('AUTH_REQUIRED') || code.contains('UNAUTHORIZED'));
  }

  static MomentPost _post(Map<String, dynamic> data) =>
      MomentPost.fromJson(momentsMap(data['post'] ?? data['moment'] ?? data));
  static Map<String, dynamic> _pageQuery(String? cursor, int size) =>
      {if (cursor != null) 'cursor': cursor, 'limit': size.clamp(1, 50)};
  static String _id(String id) {
    if (id.trim().isEmpty || id != id.trim()) {
      throw const FormatException('Missing moments ID');
    }
    return Uri.encodeComponent(id);
  }

  static void _validateAudience(String visibility, List<String> audience) {
    if (!const ['SELF', 'FRIENDS', 'PARTIAL', 'EXCLUDE'].contains(visibility) ||
        visibility == 'PARTIAL' && audience.isEmpty ||
        const ['SELF', 'FRIENDS'].contains(visibility) && audience.isNotEmpty) {
      throw const MomentsException('请选择有效的可见范围');
    }
    for (final id in audience) {
      _id(id);
    }
  }
}
