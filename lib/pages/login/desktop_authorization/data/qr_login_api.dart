import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';
import 'desktop_authorization_service.dart';

class QrLoginFailure implements Exception {
  const QrLoginFailure(this.code);
  final int code;
  String get message => switch (code) {
        202 => '请求正在处理中，请稍后重试',
        400 => '请求或校验码无效，请核对电脑上的数字',
        401 => '登录状态已失效，请重新登录后扫码',
        403 => '无法授权，请核对校验码及当前登录设备',
        409 => '请求状态已变化，请在电脑上查看结果或重新扫码',
        410 => '二维码已过期，请在电脑上刷新后重新扫码',
        426 => '当前版本暂不支持，请更新后重试',
        429 => '操作过于频繁，请稍后重试',
        503 => '登录服务暂不可用，请稍后重试',
        -1 => '连接中断或超时，结果尚未确认，请重试',
        _ => '登录服务返回异常，请稍后重试',
      };
  @override
  String toString() => 'QrLoginFailure($code)';
}

/// Dedicated transport: no shared logging interceptors, redirects, or token URLs.
class QrLoginApi implements DesktopAuthorizationService {
  QrLoginApi({Dio? transport, String? baseUrl})
      : _dio = transport ??
            Dio(BaseOptions(connectTimeout: const Duration(seconds: 15))),
        _baseUrl = baseUrl ?? Config.appAuthUrl,
        _owner = (DataSp.userID, DataSp.chatToken);
  final Dio _dio;
  final String _baseUrl;
  final (String?, String?) _owner;
  final _sessions = <String, (String, DesktopAuthorization)>{};

  void _checkOwner() {
    if (_owner.$1?.isNotEmpty != true ||
        _owner.$2?.isNotEmpty != true ||
        _owner != (DataSp.userID, DataSp.chatToken)) {
      _sessions.clear();
      throw const QrLoginFailure(401);
    }
  }

  Future<Map<String, dynamic>> _post(
      String action, Map<String, dynamic> data) async {
    _checkOwner();
    final base = Uri.parse(_baseUrl);
    if (!['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const QrLoginFailure(503);
    }
    try {
      final response = await _dio.post<dynamic>(
        '${_baseUrl.replaceFirst(RegExp(r'/+$'), '')}/account/qr-login/$action',
        data: data,
        options: Options(
            headers: {'token': _owner.$2},
            contentType: Headers.jsonContentType,
            followRedirects: false,
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15)),
      );
      _checkOwner();
      final body = response.data;
      if (body is! Map || body['errCode'] is! int) {
        throw const QrLoginFailure(500);
      }
      if (body['errCode'] != 0) throw QrLoginFailure(body['errCode'] as int);
      if (body['data'] is! Map) throw const QrLoginFailure(500);
      return Map<String, dynamic>.from(body['data'] as Map);
    } on DioException catch (error) {
      _checkOwner();
      throw QrLoginFailure(error.response?.statusCode ?? -1);
    }
  }

  @override
  Future<DesktopAuthorization> scan(String id) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(id)) {
      throw const QrLoginFailure(400);
    }
    final data = await _post('scan', {'sessionID': id});
    final nonce = data['confirmNonce'];
    if (data['sessionID'] != id ||
        nonce is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{32,64}$').hasMatch(nonce) ||
        ![3, 4].contains(data['platform']) ||
        data['deviceName'] is! String ||
        data['expiresAt'] is! int ||
        data['verificationRequired'] != true) {
      throw const QrLoginFailure(500);
    }
    final value = DesktopAuthorization(
        deviceName: data['deviceName'] as String,
        platform: data['platform'] == 3 ? 'Windows' : 'Mac',
        region: '设备名称由电脑提供',
        expiresAt:
            DateTime.fromMillisecondsSinceEpoch(data['expiresAt'] as int),
        state: DesktopAuthorizationState.scanned);
    if (!DateTime.now().isBefore(value.expiresAt)) {
      _sessions.remove(id);
      throw const QrLoginFailure(410);
    }
    _sessions[id] = (nonce, value);
    return value;
  }

  @override
  Future<DesktopAuthorization> confirm(String id,
      {String verificationCode = ''}) async {
    _checkOwner();
    final session = _sessions[id];
    if (session != null && !DateTime.now().isBefore(session.$2.expiresAt)) {
      _sessions.remove(id);
      throw const QrLoginFailure(410);
    }
    if (session == null || !RegExp(r'^[0-9]{6}$').hasMatch(verificationCode)) {
      throw const QrLoginFailure(400);
    }
    final data = await _post('confirm', {
      'sessionID': id,
      'confirmNonce': session.$1,
      'verificationCode': verificationCode
    });
    if (data['state'] != 'approved') throw const QrLoginFailure(500);
    return DesktopAuthorization(
        deviceName: session.$2.deviceName,
        platform: session.$2.platform,
        expiresAt: session.$2.expiresAt,
        state: DesktopAuthorizationState.approved);
  }

  @override
  Future<void> cancel(String id) async {
    _checkOwner();
    final session = _sessions[id];
    if (session == null) return;
    await _post('reject', {'sessionID': id, 'confirmNonce': session.$1});
    _sessions.remove(id);
  }

  // The published status API requires the computer's private proof.
  @override
  Future<DesktopAuthorization> status(String id) async =>
      throw const DesktopAuthorizationUnavailable();
}
