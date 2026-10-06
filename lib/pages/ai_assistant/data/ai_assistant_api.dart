import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'ai_assistant_contract.dart';
import 'ai_assistant_exception.dart';
import 'ai_assistant_stream_client.dart';
import 'ai_assistant_transport.dart';
import 'ai_assistant_upload_mime.dart';

export 'ai_assistant_contract.dart';
export 'ai_assistant_exception.dart';

/// Contract adapter for a real AI gateway, independent of the IM SDK.
/// The current workspace contains no server implementation of these routes.
class AiAssistantApi {
  AiAssistantApi({Dio? dio, String? baseUrl, String? Function()? tokenProvider,
    String? Function()? userProvider})
      : _transport = AiAssistantTransport(dio: dio, baseUrl: baseUrl,
            tokenProvider: tokenProvider, userProvider: userProvider);

  static final instance = AiAssistantApi();
  static const prefix = '/ai-assistant/api/v1/chat';
  final AiAssistantTransport _transport;

  static void _validateId(String id) {
    if (id.trim().isEmpty || id.length > 512 || id == '.' || id == '..' || id.contains(RegExp(r'[\r\n]'))) {
      throw const AiAssistantException('INVALID_INPUT', '无效的助手文件');
    }
  }
  static String filePath(String fileId) {
    _validateId(fileId);
    return '$prefix/files/${Uri.encodeComponent(fileId)}';
  }
  static String? fileIdFromUrl(String? url) {
    final raw = url?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final path = Uri.parse(raw).path;
      const marker = '/api/v1/chat/files/';
      final index = path.indexOf(marker);
      final id = index < 0 ? (raw.contains('/') ? '' : raw) : Uri.decodeComponent(path.substring(index + marker.length));
      _validateId(id);
      return id;
    } catch (_) { return null; }
  }

  Future<AiAssistantHistoryPage> history({int limit = 50, String? cursor, CancelToken? cancelToken}) async {
    final response = await _transport.request<dynamic>('$prefix/history', query: {
      'limit': limit.clamp(1, 100), if (cursor?.trim().isNotEmpty == true) 'cursor': cursor!.trim(),
    }, cancelToken: cancelToken);
    final payload = _transport.payload(response);
    if (payload is! Map || payload['items'] is! List || payload['hasMore'] is! bool ||
        (payload['hasMore'] == true && (payload['nextCursor'] is! String || (payload['nextCursor'] as String).isEmpty))) {
      throw const AiAssistantException('INVALID_RESPONSE', '历史记录数据不完整，请重试');
    }
    final items = payload['items'] as List;
    if (items.any((item) => item is! Map || !{'user', 'assistant'}.contains(item['role']) || item['id'] is! String || (item['id'] as String).isEmpty || item['content'] is! String)) {
      throw const AiAssistantException('INVALID_RESPONSE', '历史记录数据不完整，请重试');
    }
    return AiAssistantHistoryPage.fromJson(Map<String, dynamic>.from(payload));
  }

  Future<int> deleteHistory({CancelToken? cancelToken}) async {
    final response = await _transport.request<dynamic>('$prefix/history', method: 'DELETE', cancelToken: cancelToken);
    final payload = _transport.payload(response);
    if (payload is! Map || payload['deleted'] is! num || payload['deleted'] < 0) {
      throw const AiAssistantException('INVALID_RESPONSE', '清空结果尚未确认，请刷新后查看');
    }
    return (payload['deleted'] as num).toInt();
  }

  Future<AiAssistantUploadedFile> uploadFile({required String fileName, String? path,
      Uint8List? bytes, String? mimeType, CancelToken? cancelToken}) async {
    final owner = _transport.session();
    final name = AiAssistantUploadMime.ensureFileName(fileName, mimeType);
    final mime = AiAssistantUploadMime.fromName(name);
    if (mime == null || !AiAssistantUploadMime.allowedMimes.contains(mime) || !AiAssistantUploadMime.matchesMime(name, mimeType)) {
      throw const AiAssistantException('INVALID_INPUT', '仅支持图片、表格、视频或PDF');
    }
    final MultipartFile part;
    if (bytes != null && bytes.isNotEmpty) {
      if (bytes.length > AiAssistantUploadMime.maxBytes) throw const AiAssistantException('FILE_TOO_LARGE', '文件不能超过20MB');
      part = MultipartFile.fromBytes(bytes, filename: name, contentType: DioMediaType.parse(mime));
    } else {
      if (path?.trim().isNotEmpty != true) throw const AiAssistantException('INVALID_INPUT', '文件不可用');
      final file = File(path!);
      if (!await file.exists()) throw const AiAssistantException('FILE_UNAVAILABLE', '文件不可用');
      final size = await file.length();
      if (size <= 0) throw const AiAssistantException('FILE_UNAVAILABLE', '文件不可用');
      if (size > AiAssistantUploadMime.maxBytes) throw const AiAssistantException('FILE_TOO_LARGE', '文件不能超过20MB');
      part = await MultipartFile.fromFile(path, filename: name, contentType: DioMediaType.parse(mime));
    }
    final response = await _transport.request<dynamic>('$prefix/files', method: 'POST',
        body: FormData.fromMap({'file': part}), cancelToken: cancelToken, captured: owner);
    final payload = _transport.payload(response);
    if (payload is! Map) throw const AiAssistantException('INVALID_RESPONSE', '上传未返回有效数据');
    final file = AiAssistantUploadedFile.fromJson(Map<String, dynamic>.from(payload));
    try {
      _validateId(file.fileId);
    } on AiAssistantException {
      throw const AiAssistantException('INVALID_RESPONSE', '上传未返回有效文件');
    }
    return file;
  }

  Future<Uint8List> downloadFile(String fileId, {CancelToken? cancelToken}) async {
    final response = await _transport.request<List<int>>(filePath(fileId), responseType: ResponseType.bytes, cancelToken: cancelToken);
    final status = response.statusCode ?? 0;
    if (status != 200) throw _transport.failure(null, status);
    final bytes = response.data;
    final type = (response.headers.value(Headers.contentTypeHeader) ?? '').toLowerCase();
    if (bytes == null || bytes.isEmpty || type.contains('json') || type.contains('text/html')) {
      throw const AiAssistantException('FILE_UNAVAILABLE', '文件不可用');
    }
    return Uint8List.fromList(bytes);
  }

  Stream<AiAssistantStreamEvent> streamChat({String? capability, required String content,
    AiAssistantAnalyze? analyze, List<String>? fileIds, CancelToken? cancelToken}) {
    final body = <String, dynamic>{'content': content,
      if (capability?.trim().isNotEmpty == true) 'capability': capability!.trim(),
      if (analyze != null) 'analyze': analyze.toJson(),
      if (fileIds?.isNotEmpty == true) 'fileIds': fileIds,
    };
    return AiAssistantStreamClient(_transport).open('$prefix/stream', body, cancelToken: cancelToken);
  }

  Stream<AiAssistantStreamEvent> stream({String? capability, required String content,
    AiAssistantAnalyze? analyze, List<String>? fileIds, CancelToken? cancelToken}) =>
      streamChat(capability: capability, content: content, analyze: analyze, fileIds: fileIds, cancelToken: cancelToken);
}
