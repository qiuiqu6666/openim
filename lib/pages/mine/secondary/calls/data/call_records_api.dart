import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

class CallRecordsException implements Exception {
  const CallRecordsException(this.code, this.message);
  final Object code;
  final String message;
  @override
  String toString() => message;
}

class CallRecordsPage {
  const CallRecordsPage({required this.records, required this.syncAt});
  final List<CallRecords> records;
  final int syncAt;
}

/// Chat business HTTP identity; the SDK IM token is never used here.
class CallRecordsApi {
  CallRecordsApi({Dio? client, String? baseUrl})
      : _client = client ?? dio,
        _baseUrl = baseUrl;
  final Dio _client;
  final String? _baseUrl;
  String get baseUrl {
    final value =
        (_baseUrl ?? Config.appAuthUrl).replaceFirst(RegExp(r'/+$'), '');
    return value.endsWith('/chat')
        ? value.substring(0, value.length - '/chat'.length)
        : value;
  }

  static int _integer(Map json, String field) {
    final value = json[field];
    if (value is! int || value < 0) {
      throw FormatException('Invalid call-record $field');
    }
    return value;
  }

  static String _string(Map json, String field, {bool allowEmpty = false}) {
    final value = json[field];
    if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
      throw FormatException('Invalid call-record $field');
    }
    return value;
  }

  static CallRecords decodeRecord(Object? value) {
    if (value is! Map) throw const FormatException('Invalid call record');
    final callID = _string(value, 'callID');
    if (!RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(callID)) {
      throw const FormatException('Invalid call-record identifier');
    }
    final media = _string(value, 'mediaType');
    final room = _string(value, 'roomType');
    final direction = _string(value, 'direction');
    final status = _string(value, 'status');
    if (!const {'audio', 'video'}.contains(media) ||
        !const {'single', 'group'}.contains(room) ||
        !const {'in', 'out'}.contains(direction) ||
        !const {'completed', 'missed', 'rejected', 'cancelled'}
            .contains(status)) {
      throw const FormatException('Invalid call-record classification');
    }
    final peer = _string(value, 'peerUserID', allowEmpty: room == 'group');
    final group = _string(value, 'groupID', allowEmpty: room == 'single');
    final startedAt = _integer(value, 'startedAt');
    final endedAt = _integer(value, 'endedAt');
    if (endedAt != 0 &&
        (endedAt < startedAt || endedAt - startedAt > 86400000)) {
      throw const FormatException('Invalid call-record time range');
    }
    final duration = _integer(value, 'duration');
    if (duration > 86400) {
      throw const FormatException('Invalid call-record duration');
    }
    return CallRecords(
      roomID: callID,
      userID: peer,
      nickname: '',
      type: media,
      incomingCall: direction == 'in',
      success: status == 'completed',
      state: status,
      duration: status == 'completed' ? duration : 0,
      date: startedAt,
      endedAt: endedAt,
      updatedAt: _integer(value, 'updatedAt'),
      roomType: room,
      groupID: group,
    );
  }

  Future<Map<String, dynamic>> _request(String token,
      {String method = 'GET',
      Map<String, dynamic>? query,
      Map<String, dynamic>? data}) async {
    if (token.trim().isEmpty) {
      throw const CallRecordsException('AUTH_INVALID', '请先登录');
    }
    Response<dynamic> response;
    try {
      response = await _client.request<dynamic>('$baseUrl/chat/call-records',
          queryParameters: query,
          data: data,
          options: Options(
              method: method,
              headers: {'token': token, 'operationID': const Uuid().v4()},
              contentType: Headers.jsonContentType,
              followRedirects: false,
              validateStatus: (_) => true));
    } on DioException {
      throw const CallRecordsException('NETWORK_ERROR', '通话记录暂时无法同步，请稍后重试。');
    }
    final body = response.data;
    if (body is! Map || body['errCode'] is! int) {
      throw const FormatException('Invalid call-record response');
    }
    if (body['errCode'] != 0) {
      // Do not surface upstream debugging details in the user's call list.
      throw CallRecordsException(body['errCode'], '通话记录暂时无法同步，请稍后重试。');
    }
    final status = response.statusCode;
    if (status == null || status < 200 || status >= 300) {
      throw const CallRecordsException('HTTP_ERROR', '通话记录暂时无法同步，请稍后重试。');
    }
    final payload = body['data'];
    if (payload is! Map) {
      throw const FormatException('Missing call-record response data');
    }
    return Map<String, dynamic>.from(payload);
  }

  Future<CallRecordsPage> page(
      {required int syncAt, int limit = 200, required String token}) async {
    if (syncAt < 0 || limit < 1 || limit > 500) {
      throw ArgumentError('Invalid call-record pagination');
    }
    final data =
        await _request(token, query: {'syncAt': syncAt, 'limit': limit});
    final records = data['records'];
    if (records is! List) {
      throw const FormatException('Missing call-record page records');
    }
    return CallRecordsPage(
        records: records.map(decodeRecord).toList(),
        syncAt: _integer(data, 'syncAt'));
  }

  Future<CallRecords> report(CallRecords record,
      {required String token}) async {
    final data = <String, dynamic>{
      'callID': record.callID,
      'mediaType': record.type,
      'roomType': record.roomType,
      'direction': record.incomingCall ? 'in' : 'out',
      'status': record.status,
      'peerUserID': record.userID,
      'groupID': record.groupID,
      'participantUserIDs': record.participantUserIDs.toSet().toList(),
      'duration': record.status == 'completed' ? record.duration : 0,
      'startedAt': record.startedAt,
      'endedAt': record.endedAt,
    };
    // Validate the same scalar contract before sending user-provided values.
    decodeRecord({...data, 'updatedAt': 0});
    if (record.participantUserIDs.length > 100 ||
        record.participantUserIDs.any((id) => id.trim().isEmpty)) {
      throw ArgumentError('Invalid call-record participant');
    }
    final response =
        decodeRecord(await _request(token, method: 'POST', data: data));
    if (response.callID != record.callID ||
        response.type != record.type ||
        response.roomType != record.roomType ||
        response.incomingCall != record.incomingCall ||
        response.userID != record.userID ||
        response.groupID != record.groupID) {
      throw const FormatException('Call-record acknowledgement mismatch');
    }
    return response;
  }
}
