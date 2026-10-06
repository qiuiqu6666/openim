import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';
import 'ai_assistant_exception.dart';

/// Uses this application's business identity and a fixed gateway origin.
/// Reference 99chat JWTs and IM credentials never enter this transport.
class AiAssistantTransport {
  AiAssistantTransport({Dio? dio, String? baseUrl,
    String? Function()? tokenProvider, String? Function()? userProvider})
      : client = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 30))),
        _baseUrl = baseUrl,
        _tokenProvider = tokenProvider ?? (() => DataSp.chatToken),
        _userProvider = userProvider ?? (() => DataSp.userID);

  final Dio client;
  final String? _baseUrl;
  final String? Function() _tokenProvider, _userProvider;
  String get baseUrl => (_baseUrl ?? Config.appAuthUrl).replaceFirst(RegExp(r'/+$'), '');

  ({String token, String user, String base}) session() {
    final token = _tokenProvider()?.trim() ?? '';
    final user = _userProvider()?.trim() ?? '';
    final base = baseUrl;
    final uri = Uri.tryParse(base);
    if (token.isEmpty || user.isEmpty) {
      throw const AiAssistantException('UNAUTHORIZED', '请先登录后使用助手');
    }
    if (uri == null || !{'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const AiAssistantException('SERVICE_UNAVAILABLE', '助手服务地址未配置');
    }
    return (token: token, user: user, base: base);
  }

  void check(({String token, String user, String base}) captured) {
    if (captured.token != _tokenProvider()?.trim() ||
        captured.user != _userProvider()?.trim() || captured.base != baseUrl) {
      throw const AiAssistantException('SESSION_CHANGED', '登录状态已变化，请重新进入助手');
    }
  }

  Future<Response<T>> request<T>(String path, {
    String method = 'GET', dynamic body, Map<String, dynamic>? query,
    ResponseType responseType = ResponseType.json, CancelToken? cancelToken,
    ({String token, String user, String base})? captured,
  }) async {
    final owner = captured ?? session();
    check(owner);
    if (!path.startsWith('/') || path.startsWith('//') || path.contains(RegExp(r'[\r\n]'))) {
      throw const AiAssistantException('INVALID_INPUT', '无效的助手接口');
    }
    try {
      final response = await client.request<T>('${owner.base}$path', data: body,
        queryParameters: query, cancelToken: cancelToken,
        options: Options(method: method, responseType: responseType,
          followRedirects: false, validateStatus: (_) => true,
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: responseType == ResponseType.stream ? Duration.zero : const Duration(seconds: 60),
          headers: <String, dynamic>{
            // Clear inherited headers when tests inject a configured client.
            'Authorization': null, 'token': owner.token, 'operationID': const Uuid().v4(),
            if (responseType == ResponseType.stream) 'Accept': 'text/event-stream',
          },
          contentType: body is FormData ? Headers.multipartFormDataContentType : Headers.jsonContentType));
      check(owner);
      return response;
    } on DioException catch (error) {
      check(owner);
      if (CancelToken.isCancel(error)) throw const AiAssistantException('CANCELLED', '');
      throw const AiAssistantException('MAIN_UNAVAILABLE', '助手暂时不可用，请稍后重试');
    }
  }

  dynamic payload(Response<dynamic> response) {
    final raw = response.data;
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) throw failure(raw, status);
    if (raw is! Map) throw const AiAssistantException('INVALID_RESPONSE', '助手返回的数据格式不正确');
    final code = raw['errCode'] ?? raw['errorCode'] ?? raw['code'];
    if (code != null && !{'0', '200', '201', 'OK', 'SUCCESS'}.contains('$code'.toUpperCase())) {
      throw failure(raw, status);
    }
    return code == null ? raw : raw['data'] ?? raw['result'] ?? raw['payload'];
  }

  AiAssistantException failure(dynamic raw, int status) {
    if (status == 404 || status == 501) {
      return const AiAssistantException('SERVICE_UNAVAILABLE', '当前服务器尚未接入AI助手服务');
    }
    Map? map;
    if (raw is Map) map = raw;
    if (raw is String) {
      try { final decoded = jsonDecode(raw); if (decoded is Map) map = decoded; } on FormatException { /* Gateway HTML is not user-facing text. */ }
    }
    final code = map?['errCode'] ?? map?['errorCode'] ?? map?['code'];
    final text = map?['errMsg'] ?? map?['message'] ?? map?['msg'];
    final authCode = {'1501', '1503', '1504', '1505', '1506', '1507', '20101'}.contains('$code');
    if (status == 401 || authCode) return const AiAssistantException('UNAUTHORIZED', '登录已失效，请重新登录');
    if (status == 403) return const AiAssistantException('FORBIDDEN', '你没有使用该功能的权限');
    if (status == 409) return const AiAssistantException('CHAT_BUSY', '上一条回复还在生成中');
    final resolvedCode = code != null && '$code' != '0' ? '$code' : status == 400 ? 'INVALID_INPUT' : 'MAIN_UNAVAILABLE';
    final message = text is String && text.length <= 200 && !text.contains(RegExp(r'(https?://|goroutine|/tmp/|Bearer\s)'))
        ? text.trim() : '';
    return AiAssistantException(resolvedCode, message.isEmpty ? '助手暂时不可用，请稍后重试' : message);
  }
}
