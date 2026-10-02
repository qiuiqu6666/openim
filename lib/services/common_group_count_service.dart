import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

class CommonGroupsException implements Exception {
  const CommonGroupsException(this.code);
  final int code;
}

class CommonGroupListPage {
  const CommonGroupListPage(
      {required this.items, required this.nextCursor, required this.hasMore});
  final List<GroupInfo> items;
  final String nextCursor;
  final bool hasMore;
}

/// Uses Chat's count and cursor APIs without scanning SDK groups.
class CommonGroupCountService {
  CommonGroupCountService({Dio? client}) : _client = client ?? dio;
  final Dio _client;

  String _url(String peer) {
    if (peer.isEmpty || peer.runes.length > 128) {
      throw ArgumentError.value(peer, 'peerUserID');
    }
    return '${Config.appAuthUrl}/chat/users/${Uri.encodeComponent(peer)}/common-groups';
  }

  Future<Map> _get(
      String url, Map<String, dynamic>? query, CancelToken? cancelToken) async {
    final response = await _client.get(url,
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(headers: {
          'token': DataSp.chatToken,
          'operationID': HttpUtil.operationID
        }));
    final body = response.data;
    if (body is! Map || body['errCode'] is! int) {
      throw const FormatException('Invalid common groups response');
    }
    if (body['errCode'] != 0) {
      throw CommonGroupsException(body['errCode'] as int);
    }
    if (body['data'] is! Map) {
      throw const FormatException('Missing common groups data');
    }
    return body['data'] as Map;
  }

  Future<int> count(String peerUserID, {CancelToken? cancelToken}) async {
    final data = await _get('${_url(peerUserID)}/count', null, cancelToken);
    final total = data['total'];
    if (total is! int || total < 0) {
      throw const FormatException('Invalid common groups total');
    }
    return total;
  }

  Future<CommonGroupListPage> list(String peerUserID,
      {int limit = 30, String cursor = '', CancelToken? cancelToken}) async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit, 'limit');
    final data = await _get(
        _url(peerUserID), {'limit': limit, 'cursor': cursor}, cancelToken);
    if (data['items'] is! List ||
        data['nextCursor'] is! String ||
        data['hasMore'] is! bool) {
      throw const FormatException('Invalid common groups page');
    }
    final next = data['nextCursor'] as String;
    final more = data['hasMore'] as bool;
    if (more && (next.isEmpty || next == cursor)) {
      throw const FormatException('Cursor did not advance');
    }
    final items = (data['items'] as List).map((item) {
      if (item is! Map ||
          item['groupID'] is! String ||
          (item['groupID'] as String).isEmpty ||
          item['groupName'] is! String ||
          item['faceURL'] is! String ||
          item['memberCount'] is! int ||
          (item['memberCount'] as int) < 0) {
        throw const FormatException('Invalid common group');
      }
      return GroupInfo.fromJson(Map<String, dynamic>.from(item));
    }).toList();
    return CommonGroupListPage(items: items, nextCursor: next, hasMore: more);
  }
}
