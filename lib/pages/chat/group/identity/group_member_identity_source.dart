import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

import 'group_member_identity_incremental.dart';
import 'group_member_identity_info.dart';

typedef GroupMemberIdentityPoster = Future<dynamic> Function(
  String url,
  Map<String, dynamic> data,
  Options options,
);

class GroupMemberIdentitySessionChanged implements Exception {
  const GroupMemberIdentitySessionChanged();

  @override
  String toString() => 'Group member identity session changed';
}

/// Reads accounts only from IM group endpoints, without a user-directory fallback.
class GroupMemberIdentitySource {
  GroupMemberIdentitySource({
    GroupMemberIdentityPoster? poster,
    Dio? client,
    void Function(int code)? onAuthFailure,
    String? Function()? currentUserID,
    String? Function()? currentToken,
    String? Function()? sdkUserID,
    String Function()? baseURL,
  })  : _poster = poster,
        _client = client ?? _newClient(),
        _onAuthFailure =
            onAuthFailure ?? (poster == null ? _reportAuthFailure : null),
        _currentUserID = currentUserID ?? (() => DataSp.userID),
        _currentToken = currentToken ?? (() => DataSp.imToken),
        _sdkUserID = sdkUserID ?? _readSdkUserID,
        _baseURL = baseURL ?? (() => Config.imApiUrl);

  final GroupMemberIdentityPoster? _poster;
  final Dio _client;
  final void Function(int code)? _onAuthFailure;
  final String? Function() _currentUserID;
  final String? Function() _currentToken;
  final String? Function() _sdkUserID;
  final String Function() _baseURL;

  Future<List<GroupMemberIdentityInfo>> list({
    required String groupID,
    int pageNumber = 1,
    int showNumber = 20,
    int filter = 0,
    String keyword = '',
  }) async {
    _requiredID(groupID);
    if (pageNumber < 1 || showNumber < 1) {
      throw ArgumentError('Invalid group member pagination');
    }
    final data = await _request('/group/get_group_member_list', {
      'groupID': groupID,
      'pagination': {'pageNumber': pageNumber, 'showNumber': showNumber},
      'filter': filter,
      'keyword': keyword,
    });
    return _scopedMembers(data['members'], groupID);
  }

  Future<List<GroupMemberIdentityInfo>> members({
    required String groupID,
    required List<String> userIDList,
  }) async {
    _requiredID(groupID);
    for (final userID in userIDList) {
      _requiredID(userID);
    }
    if (userIDList.isEmpty) return const [];
    final requestedUserIDs = Set<String>.of(userIDList);
    final data = await _request('/group/get_group_members_info', {
      'groupID': groupID,
      'userIDs': List<String>.of(userIDList),
    });
    return _scopedMembers(data['members'], groupID, userIDs: requestedUserIDs);
  }

  Future<GroupMemberIdentityIncremental> incremental({
    required String groupID,
    String versionID = '',
    int version = 0,
  }) async {
    final cursor = GroupMemberIdentityVersion(
      groupID: groupID,
      versionID: versionID,
      version: version,
    );
    _validateVersion(cursor);
    final data =
        await _request('/group/get_incremental_group_members', cursor.toJson());
    return _scopedIncremental(data, groupID);
  }

  Future<Map<String, GroupMemberIdentityIncremental>> batch({
    required List<GroupMemberIdentityVersion> reqList,
  }) async {
    for (final cursor in reqList) {
      _validateVersion(cursor);
    }
    if (reqList.isEmpty) return const {};
    final requestedGroups = reqList.map((cursor) => cursor.groupID).toSet();
    final data = await _request(
        '/group/get_incremental_group_members_batch',
        {
          'reqList': reqList.map((cursor) => cursor.toJson()).toList(),
        },
        includeUserID: true);
    final values = data['respList'];
    if (values == null) return const {};
    if (values is! Map) {
      throw const FormatException('Invalid group member batch');
    }
    final results = <String, GroupMemberIdentityIncremental>{};
    for (final entry in values.entries) {
      if (!requestedGroups.contains(entry.key)) continue;
      if (entry.value is! Map) {
        throw const FormatException('Invalid group member batch entry');
      }
      results[entry.key as String] = _scopedIncremental(
          Map<String, dynamic>.from(entry.value as Map), entry.key as String);
    }
    return Map<String, GroupMemberIdentityIncremental>.unmodifiable(results);
  }

  Future<Map<String, dynamic>> _request(String path, Map<String, dynamic> data,
      {bool includeUserID = false}) async {
    final userID = _currentUserID();
    final token = _currentToken();
    final sdkUserID = _sdkUserID();
    final server = _baseURL();
    if (userID?.trim().isNotEmpty != true || token?.isNotEmpty != true) {
      throw StateError('Group member identity requires an IM session');
    }
    bool isCurrent() =>
        userID == _currentUserID() &&
        token == _currentToken() &&
        sdkUserID == _sdkUserID() &&
        server == _baseURL();
    final url = '${server.replaceFirst(RegExp(r'/+$'), '')}$path';
    final options = Options(
      contentType: Headers.jsonContentType,
      headers: {'token': token, 'operationID': const Uuid().v4()},
    );
    final dynamic response;
    try {
      response = await (_poster ?? _defaultPost)(
          url, {...data, if (includeUserID) 'userID': userID}, options);
    } catch (_) {
      if (!isCurrent()) throw const GroupMemberIdentitySessionChanged();
      rethrow;
    }
    if (!isCurrent()) throw const GroupMemberIdentitySessionChanged();
    if (response is! Map) {
      throw const FormatException('Invalid group member response');
    }
    // Injected transports may return decoded data; real HTTP returns the envelope.
    final dynamic body;
    if (response.containsKey('errCode')) {
      final result = ApiResp.fromJson(Map<String, dynamic>.from(response));
      if (result.errCode != 0) {
        // Match shared HTTP auth codes, after this request's complete session guard.
        if (result.errCode == 1506 || result.errCode == 20101) {
          _onAuthFailure?.call(result.errCode);
        }
        throw (
          result.errCode,
          result.errDlt.isNotEmpty ? result.errDlt : result.errMsg
        );
      }
      body = result.data;
    } else {
      body = response;
    }
    if (body is! Map) {
      throw const FormatException('Invalid group member data');
    }
    return Map<String, dynamic>.from(body);
  }

  Future<dynamic> _defaultPost(
      String url, Map<String, dynamic> data, Options options) async {
    final response = await _client.post<Map<String, dynamic>>(
      url,
      data: data,
      options: options,
    );
    return response.data;
  }

  static Dio _newClient() => Dio(dio.options.copyWith(
        connectTimeout:
            dio.options.connectTimeout ?? const Duration(seconds: 30),
        receiveTimeout:
            dio.options.receiveTimeout ?? const Duration(seconds: 30),
      ));

  static void _reportAuthFailure(int code) => Apis.kickoffController.add(code);

  static void _requiredID(String id) {
    if (id.trim().isEmpty) throw ArgumentError('Missing group member ID');
  }

  static List<GroupMemberIdentityInfo> _scopedMembers(
      Object? values, String groupID,
      {Set<String>? userIDs}) {
    return List<GroupMemberIdentityInfo>.unmodifiable(
        parseGroupMemberIdentities(values).where((member) =>
            member.groupID == groupID &&
            member.userID?.trim().isNotEmpty == true &&
            (userIDs == null || userIDs.contains(member.userID))));
  }

  static GroupMemberIdentityIncremental _scopedIncremental(
      Map<String, dynamic> data, String groupID) {
    final group = data['group'];
    if (group != null && (group is! Map || group['groupID'] != groupID)) {
      throw const FormatException('Mismatched incremental group');
    }
    return GroupMemberIdentityIncremental.fromJson({
      ...data,
      'insert': _scopedMembers(data['insert'], groupID)
          .map((member) => member.toJson())
          .toList(),
      'update': _scopedMembers(data['update'], groupID)
          .map((member) => member.toJson())
          .toList(),
    });
  }

  static String? _readSdkUserID() {
    try {
      return OpenIM.iMManager.userID;
    } catch (_) {
      return null;
    }
  }

  static void _validateVersion(GroupMemberIdentityVersion cursor) {
    _requiredID(cursor.groupID);
    if (cursor.version < 0) throw ArgumentError('Invalid group member version');
  }
}
