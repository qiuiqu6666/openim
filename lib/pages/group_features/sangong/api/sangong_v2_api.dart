import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../../data/group_feature_api.dart';
import '../utils/api_response_util.dart';
import '../services/authorization/sangong_operation_scope.dart';
import 'sangong_game_http.dart';

/// Group identity is part of the URL; a client-supplied tenant never selects an
/// account. The host resolves agent groups to their bound game tenant.
class SangongV2Api {
  SangongV2Api(this.http, {this.agent = false});
  final SangongGameHttp http;
  final bool agent;

  String path(String resource) =>
      '/api/v2/${agent ? 'agent-groups' : 'groups'}/'
      '${Uri.encodeComponent(http.context.groupID)}/$resource';

  Future<Map<String, dynamic>> read(String resource,
      {Map<String, dynamic>? query, bool binding = false}) async {
    final response = await http.requests.get(path(resource),
        queryParameters: query,
        options: binding
            ? Options(extra: const {SangongGameHttp.extraSkipTenant: true})
            : null);
    final data = unwrapApiPayload(response.data);
    if (data is! Map) throw const FormatException('三公接口返回格式无效');
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> command(
      String action, Map<String, dynamic> input,
      {String? requestId}) async {
    final key = jsonEncode([
      http.context.currentUserID,
      http.context.groupID,
      http.tenantId,
      agent,
      action,
      _canonical(input)
    ]);
    final id = requestId ??
        http.pendingCommandIds.putIfAbsent(key, () => const Uuid().v4());
    final response = await http.requests.post(path('commands/$action'),
        data: {'requestId': id, 'input': input});
    final envelope = response.data;
    // The Chat host may wrap the Sangong envelope once. Unwrap only the host;
    // keep the command receipt for matching the idempotency key.
    dynamic receipt = envelope;
    if (receipt is Map && receipt['errCode'] == 0) receipt = receipt['data'];
    if (receipt is! Map ||
        receipt['ok'] != true ||
        receipt['requestId'] != id ||
        receipt['data'] is! Map) {
      throw const GroupFeatureException('操作结果尚未确认，请刷新后查看',
          code: 'UNKNOWN_RESULT', unknownResult: true);
    }
    if (http.pendingCommandIds[key] == id) http.pendingCommandIds.remove(key);
    return Map<String, dynamic>.from(receipt['data']);
  }

  /// Existing team screens show the whole selected team. Fetch additional
  /// pages only when needed, and reject a changed scope/version between pages.
  Future<Map<String, dynamic>> team(
      String resource, Map<String, dynamic> query) async {
    final context = http.context;
    final tenant = http.tenantId;
    final scope = SangongOperationScope.capture(context, tenant);
    // Chat can rebuild an equivalent context during capability refresh. Agent
    // pagination pins account/group/tenant/permissions, not widget identity.
    bool current() => agent
        ? scope.matches(http.context, http.tenantId)
        : identical(context, http.context) && tenant == http.tenantId;
    final first = await read(resource, query: {...query, 'limit': 100});
    if (first['members'] is! List) throw const FormatException('团队数据无效');
    final members = List<dynamic>.from(first['members']);
    var before = _cursor(first);
    while (before > 0) {
      if (!current()) {
        throw StateError('账号或群上下文已变化，请重新进入');
      }
      final page = await read(resource,
          query: {...query, 'limit': 100, 'beforeId': before});
      if (page['version'] != first['version'] || page['members'] is! List) {
        throw StateError('团队数据已更新，请刷新后查看');
      }
      members.addAll((page['members'] as List)
          .where((row) => row is! Map || row['isSelf'] != true));
      final next = _cursor(page);
      if (next >= before) throw const FormatException('团队分页游标无效');
      before = next;
    }
    if (!current()) {
      throw StateError('账号或群上下文已变化，请重新进入');
    }
    return {...first, 'members': members, 'nextBeforeId': 0};
  }

  int _cursor(Map<String, dynamic> data) {
    final value = data['nextBeforeId'];
    if (value is! int || value < 0) {
      throw const FormatException('团队分页游标无效');
    }
    return value;
  }
}

Object? _canonical(Object? input) {
  if (input is Map<String, dynamic>) {
    final keys = input.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(input[key])};
  }
  if (input is List) return input.map(_canonical).toList();
  return input;
}
