import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:uuid/uuid.dart';
import 'package:get/get.dart';
import '../../../../core/controller/im_controller.dart';

typedef KeywordSearchSession = ({String user, String token, String server});
typedef KeywordSearchPost = Future<dynamic> Function(
    String url, Map<String, dynamic> body, Options options);

class SearchApiException implements Exception {
  const SearchApiException(this.code);
  final int code;
  bool get invalidatesContext =>
      [1002, 404, 409, 410].contains(code) || (code >= 1501 && code <= 1507);
}

/// All search endpoints share the server's per-user concurrency/rate limit.
/// A dedicated HTTP client never inherits the Chat Token or logging interceptors.
class SearchHttpClient {
  static const apiBaseUrl = String.fromEnvironment('MESSAGE_SEARCH_API_URL',
      defaultValue: 'https://99imapi.99chat.vip');
  SearchHttpClient(
      {KeywordSearchPost? post,
      KeywordSearchSession? Function()? session,
      bool? paced,
      this.reuseConnections = false})
      : _post = post,
        _paced = paced ?? post == null,
        _session = session ?? currentSession;
  final bool _paced;
  final bool reuseConnections;
  final KeywordSearchPost? _post;
  final KeywordSearchSession? Function() _session;
  KeywordSearchSession? _owner;
  static Future<void> _tail = Future.value();
  static DateTime _nextStart = DateTime.fromMillisecondsSinceEpoch(0);

  static KeywordSearchSession? currentSession() {
    final manager = OpenIM.iMManager;
    final token = manager.token;
    if (manager.userID.isEmpty || token == null || token.isEmpty) return null;
    return (user: manager.userID, token: token, server: apiBaseUrl);
  }

  bool get sessionCurrent => _owner == null || _owner == _session();

  Future<Map<String, dynamic>> request(String path, Map<String, dynamic> body,
      {bool Function()? isCurrent, CancelToken? cancelToken}) async {
    final session = _session();
    _owner ??= session;
    void check() {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      if (session == null ||
          session != _owner ||
          _session() != session ||
          isCurrent?.call() == false) {
        throw const SearchApiException(1501);
      }
    }

    check();
    Future<Map<String, dynamic>> run() async {
      check();
      final pending = (_post ??
              (url, body, options) => _defaultPost(
                  url, body, options, cancelToken, reuseConnections))(
          '${session!.server.replaceFirst(RegExp(r'/+$'), '')}$path',
          body,
          Options(contentType: Headers.jsonContentType, headers: {
            'token': session.token,
            'operationID': const Uuid().v4(),
          }));
      final response = await (cancelToken == null
          ? pending
          : Future.any<dynamic>([
              pending,
              cancelToken.whenCancel.then<dynamic>((error) => throw error),
            ]));
      check();
      if (response is! Map || response['errCode'] is! int) {
        throw const FormatException('Invalid search response');
      }
      if (response['errCode'] != 0) {
        final code = response['errCode'] as int;
        if (_post == null &&
            code >= 1501 &&
            code <= 1507 &&
            Get.isRegistered<IMController>()) {
          final im = Get.find<IMController>();
          if (code == 1501) {
            im.userTokenExpired();
          } else {
            im.userTokenInvalid();
          }
        }
        throw SearchApiException(code);
      }
      if (response['data'] is! Map) {
        throw const FormatException('Missing search data');
      }
      return Map<String, dynamic>.from(response['data'] as Map);
    }

    if (!_paced) return run();
    final result = _tail.then((_) async {
      check();
      final delay = _nextStart.difference(DateTime.now());
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      check();
      _nextStart = DateTime.now().add(const Duration(milliseconds: 1100));
      return run();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  // Keep credentials request-scoped; only sockets are reused, never responses.
  static final Dio _sharedTransport = _createTransport();

  static Dio _createTransport() => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 6),
      followRedirects: false,
      validateStatus: (code) => code != null && code < 600));

  static Future<dynamic> _defaultPost(String url, Map<String, dynamic> body,
      Options options, CancelToken? cancelToken, bool reuseConnections) async {
    final client = reuseConnections ? _sharedTransport : _createTransport();
    try {
      return (await client.post<dynamic>(url,
              data: body, options: options, cancelToken: cancelToken))
          .data;
    } finally {
      if (!reuseConnections) client.close(force: true);
    }
  }
}
