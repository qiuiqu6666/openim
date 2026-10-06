import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';
import '../models/group_features.dart';
import 'diagnostics/group_feature_api_diagnostics.dart';

class GroupFeatureException implements Exception {
  const GroupFeatureException(this.message,
      {this.code = '',
      this.unavailable = false,
      this.authRequired = false,
      this.unknownResult = false,
      this.statusCode,
      this.serverCode});
  final String message, code;
  final bool unavailable, authRequired, unknownResult;
  final int? statusCode;
  final String? serverCode;
  @override
  String toString() => message;
}

/// Business transport uses the current Chat token, never reference JWTs or IM tokens.
class GroupFeatureApi {
  GroupFeatureApi(
      {Dio? client,
      String? baseUrl,
      this.pathPrefix = '',
      String? Function()? tokenProvider,
      String Function()? userProvider})
      : _client = client ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30))),
        _baseUrl = baseUrl,
        _tokenProvider = tokenProvider,
        _userProvider = userProvider ?? (() => OpenIM.iMManager.userID);
  final Dio _client;
  final String? _baseUrl;
  final String pathPrefix;
  final String? Function()? _tokenProvider;
  final String Function() _userProvider;
  String get baseUrl =>
      (_baseUrl ?? Config.appAuthUrl).replaceFirst(RegExp(r'/+$'), '');
  String? get _token =>
      _tokenProvider != null ? _tokenProvider() : DataSp.chatToken;
  void _check(String? token, String user, String base) {
    if (token == null ||
        token.isEmpty ||
        user.isEmpty ||
        token != _token ||
        user != _userProvider() ||
        base != baseUrl) {
      throw const GroupFeatureException('登录状态已变化，请重新进入',
          code: 'SESSION_CHANGED', authRequired: true);
    }
  }

  String? _serverCodeOf(dynamic raw) {
    final map = featureMap(raw);
    for (final value in [
      map['code'],
      map['errorCode'],
      map['errCode'],
      featureMap(map['error'])['code'],
    ]) {
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> get(String path,
          {Map<String, dynamic>? query,
          Map<String, dynamic>? headers,
          CancelToken? cancelToken}) =>
      request(path, query: query, headers: headers, cancelToken: cancelToken);
  Future<Map<String, dynamic>> post(String path,
          {Map<String, dynamic>? body,
          Map<String, dynamic>? query,
          Map<String, dynamic>? headers,
          CancelToken? cancelToken}) =>
      request(path,
          method: 'POST',
          body: body,
          query: query,
          headers: headers,
          cancelToken: cancelToken);
  Future<Map<String, dynamic>> put(String path,
          {Map<String, dynamic>? body,
          Map<String, dynamic>? query,
          Map<String, dynamic>? headers,
          CancelToken? cancelToken}) =>
      request(path,
          method: 'PUT',
          body: body,
          query: query,
          headers: headers,
          cancelToken: cancelToken);
  Future<Map<String, dynamic>> patch(String path,
          {Map<String, dynamic>? body,
          Map<String, dynamic>? query,
          Map<String, dynamic>? headers,
          CancelToken? cancelToken}) =>
      request(path,
          method: 'PATCH',
          body: body,
          query: query,
          headers: headers,
          cancelToken: cancelToken);
  Future<Map<String, dynamic>> delete(String path,
          {Map<String, dynamic>? body,
          Map<String, dynamic>? query,
          Map<String, dynamic>? headers,
          CancelToken? cancelToken}) =>
      request(path,
          method: 'DELETE',
          body: body,
          query: query,
          headers: headers,
          cancelToken: cancelToken);
  Future<dynamic> getData(String path,
          {Map<String, dynamic>? query,
          Map<String, dynamic>? headers,
          CancelToken? cancelToken}) =>
      requestData(path,
          query: query, headers: headers, cancelToken: cancelToken);

  /// Keeps pagination and server metadata for services whose data can be a list.
  Future<Map<String, dynamic>> getEnvelope(String path,
      {Map<String, dynamic>? query,
      Map<String, dynamic>? headers,
      CancelToken? cancelToken}) async {
    final raw = await requestData(path,
        query: query,
        headers: headers,
        cancelToken: cancelToken,
        preserveEnvelope: true);
    if (raw is! Map) {
      throw const GroupFeatureException('服务返回的数据格式不正确',
          code: 'INVALID_RESPONSE');
    }
    return featureMap(raw);
  }

  Future<Map<String, dynamic>> request(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      Map<String, dynamic>? query,
      Map<String, dynamic>? headers,
      CancelToken? cancelToken}) async {
    final data = await requestData(path,
        method: method,
        body: body,
        query: query,
        headers: headers,
        cancelToken: cancelToken);
    if (data == null && method != 'GET') return {};
    if (data is! Map) {
      throw GroupFeatureException(
          method == 'GET' ? '服务返回的数据格式不正确' : '操作结果尚未确认，请刷新后查看',
          code: method == 'GET' ? 'INVALID_RESPONSE' : 'UNKNOWN_RESULT',
          unknownResult: method != 'GET');
    }
    return featureMap(data);
  }

  Future<dynamic> requestData(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      Map<String, dynamic>? query,
      Map<String, dynamic>? headers,
      CancelToken? cancelToken,
      String? baseUrlOverride,
      bool useBearerAuth = false,
      GroupFeatureApiDiagnostics? diagnostics,
      bool preserveEnvelope = false}) async {
    final observer = diagnostics ?? scopedGroupFeatureDiagnostics();
    final token = _token, user = _userProvider(), base = baseUrl;
    _check(token, user, base);
    // A business destination may differ from Chat, but session validity still
    // belongs to the captured Chat environment.
    final targetBase =
        (baseUrlOverride ?? base).replaceFirst(RegExp(r'/+$'), '');
    final mutation = method != 'GET';
    try {
      final destination = '$targetBase$pathPrefix$path';
      final options = Options(
          method: method,
          headers: {
            ...?headers,
            if (useBearerAuth)
              'Authorization': 'Bearer $token'
            else
              'token': token,
            'operationID': const Uuid().v4()
          },
          contentType: Headers.jsonContentType,
          followRedirects: false,
          validateStatus: (_) => true);
      if (observer != null) {
        reportGroupFeatureDiagnostics(() => observer.onRequest(options.compose(
            _client.options, destination,
            data: body, queryParameters: query, cancelToken: cancelToken)));
      }
      final response = await _client.request<dynamic>(destination,
          data: body,
          queryParameters: query,
          cancelToken: cancelToken,
          options: options);
      if (observer != null) {
        reportGroupFeatureDiagnostics(() => observer.onResponse(response));
      }
      _check(token, user, base);
      final status = response.statusCode ?? 0;
      final raw = response.data;
      final map = featureMap(raw);
      final code = map['errCode'] ?? map['errorCode'] ?? map['code'];
      final serverCode = _serverCodeOf(raw);
      if (status == 404 || status == 501) {
        throw GroupFeatureException('该功能的服务暂未开通',
            code: 'SERVICE_UNAVAILABLE',
            unavailable: true,
            statusCode: status,
            serverCode: serverCode);
      }
      if (code != null &&
          !const {'0', '200', '201', 'OK', 'SUCCESS'}
              .contains('$code'.toUpperCase())) {
        if (const {'1501', '1503', '1504', '1505', '1506', '20101'}
            .contains('$code')) {
          // This local Dio instance has no HttpUtil response interceptor.
          if (_tokenProvider == null &&
              _userProvider() == OpenIM.iMManager.userID) {
            Apis.kickoffController.add(int.parse('$code'));
          }
          throw GroupFeatureException('登录已失效，请重新登录',
              code: '$code',
              authRequired: true,
              statusCode: status,
              serverCode: serverCode);
        }
        throw GroupFeatureException(
            status == 403
                ? '你没有该功能的操作权限'
                : (featureString(map['errMsg'] ?? map['message'] ?? map['msg'])
                        .isNotEmpty
                    ? featureString(
                        map['errMsg'] ?? map['message'] ?? map['msg'])
                    : '操作失败，请稍后重试'),
            code: '$code',
            statusCode: status,
            serverCode: serverCode);
      }
      if (status == 401) {
        throw GroupFeatureException('请重新登录',
            code: 'AUTH_REQUIRED',
            authRequired: true,
            statusCode: status,
            serverCode: serverCode);
      }
      if (status == 403) {
        throw GroupFeatureException('你没有该功能的操作权限',
            code: 'FORBIDDEN', statusCode: status, serverCode: serverCode);
      }
      if (status < 200 || status >= 300) {
        throw GroupFeatureException(
            mutation ? '操作结果尚未确认，请刷新后查看' : '暂时无法获取数据，请重试',
            code: 'HTTP_$status',
            unknownResult: mutation && status >= 500,
            statusCode: status,
            serverCode: serverCode);
      }
      if (preserveEnvelope) return raw;
      if (code != null) return map['data'] ?? map['result'] ?? map['payload'];
      // Some reference services return plain DTOs rather than the Chat envelope.
      return raw;
    } on DioException catch (error) {
      if (observer != null) {
        reportGroupFeatureDiagnostics(() => observer.onError(error));
      }
      _check(token, user, base);
      if (CancelToken.isCancel(error)) {
        throw GroupFeatureException('请求已取消',
            code: 'CANCELLED',
            statusCode: error.response?.statusCode,
            serverCode: _serverCodeOf(error.response?.data));
      }
      throw GroupFeatureException(mutation ? '操作结果尚未确认，请刷新后查看' : '网络连接失败，请重试',
          code: mutation ? 'UNKNOWN_RESULT' : 'NETWORK_ERROR',
          unknownResult: mutation,
          statusCode: error.response?.statusCode,
          serverCode: _serverCodeOf(error.response?.data));
    } catch (error) {
      if (observer != null) {
        reportGroupFeatureDiagnostics(() => observer.onError(error));
      }
      rethrow;
    }
  }

  Future<List<int>> getBytes(String path,
      {Map<String, dynamic>? query,
      Map<String, dynamic>? headers,
      CancelToken? cancelToken}) async {
    final token = _token, user = _userProvider(), base = baseUrl;
    _check(token, user, base);
    try {
      final response = await _client.get<List<int>>('$base$pathPrefix$path',
          queryParameters: query,
          cancelToken: cancelToken,
          options: Options(
              responseType: ResponseType.bytes,
              followRedirects: false,
              validateStatus: (_) => true,
              headers: {
                ...?headers,
                'token': token,
                'operationID': const Uuid().v4()
              }));
      _check(token, user, base);
      if (response.statusCode != 200 ||
          response.data == null ||
          (response.headers
                  .value(Headers.contentTypeHeader)
                  ?.contains('json') ??
              false)) {
        throw const GroupFeatureException('文件暂时无法下载，请重试',
            code: 'DOWNLOAD_FAILED');
      }
      return response.data!;
    } on DioException catch (_) {
      _check(token, user, base);
      throw const GroupFeatureException('文件下载失败，请重试', code: 'DOWNLOAD_FAILED');
    }
  }

  Stream<String> eventStream(String path,
      {Map<String, dynamic>? query,
      Map<String, dynamic>? headers,
      String? baseUrlOverride,
      bool useBearerAuth = false,
      GroupFeatureApiDiagnostics? diagnostics,
      CancelToken? cancelToken}) {
    final observer = diagnostics ?? scopedGroupFeatureDiagnostics();
    final token = _token, user = _userProvider(), base = baseUrl;
    final targetBase =
        (baseUrlOverride ?? base).replaceFirst(RegExp(r'/+$'), '');
    final internal = CancelToken();
    late StreamController<String> output;
    var stopped = false;
    var diagnosticsClosed = false;
    void finish() {
      if (!diagnosticsClosed) {
        diagnosticsClosed = true;
        if (observer != null) {
          reportGroupFeatureDiagnostics(observer.onStreamClosed);
        }
      }
      if (!output.isClosed) output.close();
    }

    void failed(Object error, StackTrace stack) {
      if (observer != null) {
        reportGroupFeatureDiagnostics(() => observer.onError(error));
      }
      if (!stopped &&
          !output.isClosed &&
          !(error is DioException && CancelToken.isCancel(error))) {
        output.addError(error, stack);
      }
      finish();
    }

    Future<void> open() async {
      try {
        _check(token, user, base);
        final destination = '$targetBase$pathPrefix$path';
        final options = Options(
            responseType: ResponseType.stream,
            contentType: useBearerAuth ? Headers.jsonContentType : null,
            receiveTimeout: Duration.zero,
            followRedirects: false,
            validateStatus: (_) => true,
            headers: {
              ...?headers,
              'Accept': 'text/event-stream',
              if (useBearerAuth)
                'Authorization': 'Bearer $token'
              else
                'token': token,
              'operationID': const Uuid().v4()
            });
        if (observer != null) {
          reportGroupFeatureDiagnostics(() => observer.onRequest(
              options.compose(_client.options, destination,
                  queryParameters: query, cancelToken: internal)));
        }
        final response = await _client.get<ResponseBody>(destination,
            queryParameters: query, cancelToken: internal, options: options);
        if (observer != null) {
          reportGroupFeatureDiagnostics(() => observer.onResponse(response));
        }
        _check(token, user, base);
        if (response.statusCode != 200 || response.data == null) {
          // A rejected stream is never delivered to the consumer. In debug
          // diagnostics, also show its finite JSON/text error body. Bound the
          // read so a broken server cannot keep reconnection waiting forever.
          if (observer != null && response.data != null) {
            try {
              final body = await response.data!.stream
                  .cast<List<int>>()
                  .transform(const Utf8Decoder(allowMalformed: true))
                  .join()
                  .timeout(const Duration(seconds: 2), onTimeout: () {
                internal.cancel('SSE diagnostic error-body read timed out');
                return '[错误响应读取超时]';
              });
              reportGroupFeatureDiagnostics(() => observer.onResponse(
                  Response<dynamic>(
                      requestOptions: response.requestOptions,
                      statusCode: response.statusCode,
                      headers: response.headers,
                      data: body)));
            } catch (error) {
              reportGroupFeatureDiagnostics(() => observer.onError(error));
            }
          }
          throw const GroupFeatureException('实时状态暂不可用',
              code: 'EVENT_STREAM_UNAVAILABLE', unavailable: true);
        }
        // Keep this error handler attached until Dio acknowledges cancellation.
        // Cancelling the consumer first must not leave Dio's responseSink unowned.
        response.data!.stream.cast<List<int>>().transform(utf8.decoder).listen(
            (chunk) {
          if (stopped) return;
          try {
            if (observer != null) {
              reportGroupFeatureDiagnostics(() => observer.onStreamData(chunk));
            }
            _check(token, user, base);
            output.add(chunk);
          } catch (error, stack) {
            failed(error, stack);
            internal.cancel();
          }
        }, onError: failed, onDone: finish, cancelOnError: true);
      } catch (error, stack) {
        failed(error, stack);
      }
    }

    output = StreamController<String>(
        onListen: () => unawaited(open()),
        onCancel: () {
          stopped = true;
          internal.cancel('Group feature stream closed');
        });
    cancelToken?.whenCancel
        .then((_) => internal.cancel('Group feature stream cancelled'));
    return output.stream;
  }
}
