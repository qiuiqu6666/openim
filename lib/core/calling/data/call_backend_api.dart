import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

import '../../push/apns/apns_platform.dart';
import '../../push/apns/apns_token_api.dart';

class CallBackendException implements Exception {
  const CallBackendException(this.code);
  final int code;
  @override
  String toString() => 'Call service unavailable ($code)';
}

/// Captures one authenticated account; a late cleanup never borrows a new token.
class CallBackendApi {
  CallBackendApi(
      {required this.accountID,
      required this.token,
      required this.deviceID,
      required String baseUrl,
      Dio? client})
      : baseUrl = ApnsTokenApi.normalizeBaseUrl(baseUrl),
        _dio = client ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 4),
              sendTimeout: const Duration(seconds: 4),
              followRedirects: false,
            ));

  final String accountID, token, deviceID, baseUrl;
  final Dio _dio;

  static Future<CallBackendApi> current() async {
    final account = DataSp.userID, token = DataSp.chatToken;
    final url = Config.appAuthUrl;
    if (account == null || account.isEmpty || token == null || token.isEmpty) {
      throw const CallBackendException(401);
    }
    final device = await DataSp.ensureLoginDeviceID();
    if (DataSp.userID != account ||
        DataSp.chatToken != token ||
        Config.appAuthUrl != url) {
      throw const CallBackendException(401);
    }
    return CallBackendApi(
        accountID: account, token: token, deviceID: device, baseUrl: url);
  }

  Future<Map<String, dynamic>> request(
      String path, Map<String, dynamic> data) async {
    final response = await _dio.post<Object?>('$baseUrl/calling/$path',
        data: data,
        options: Options(
            headers: {'token': token, 'operationID': const Uuid().v4()},
            followRedirects: false));
    final raw = response.data;
    if (raw is! Map || raw['errCode'] is! int) {
      throw const CallBackendException(-1);
    }
    if (raw['errCode'] != 0) throw CallBackendException(raw['errCode'] as int);
    final result = raw['data'];
    if (result is! Map || result.keys.any((key) => key is! String)) {
      throw const CallBackendException(-1);
    }
    return Map<String, dynamic>.from(result);
  }

  Future<void> bind(APNsDeviceToken value) async {
    final result = await request('voip/register', {
      'deviceID': deviceID,
      'token': value.token,
      'bundleID': value.bundleID,
      'environment': value.environment,
    });
    if (result['registered'] != true || result['deviceID'] != deviceID) {
      throw const CallBackendException(-1);
    }
  }

  Future<void> unbind() async {
    await request('voip/unregister', {'deviceID': deviceID});
  }

  Future<Map<String, dynamic>> status(String room) =>
      request('status', {'callID': room});
  Future<Map<String, dynamic>> action(String room, String action) => request(
      'action', {'callID': room, 'deviceID': deviceID, 'action': action});
  Future<Map<String, dynamic>> invite(InvitationInfo invitation) => request(
      'invite', {'deviceID': deviceID, 'invitation': invitation.toJson()});

  void close() => _dio.close();
}
