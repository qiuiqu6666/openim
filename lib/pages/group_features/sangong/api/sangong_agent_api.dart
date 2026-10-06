// Adapted from 99chat d7c3c65, Apache-2.0.
import 'package:dio/dio.dart';
import '../../data/group_feature_api.dart';
import '../models/agent_rebate_models.dart';
import 'sangong_game_http.dart';
import 'sangong_agent_response.dart';
import '../utils/api_response_util.dart';

class AgentRebateApi {
  AgentRebateApi(this.http);
  final SangongGameHttp http;
  Map<String, dynamic> _unwrapMap(dynamic data) {
    final raw = unwrapApiPayload(data);
    if (raw is! Map) {
      throw const FormatException('Invalid Sangong agent response');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<AgentEntryContextDto> fetchEntryContext(String imGroupId) async {
    final groupId = imGroupId.trim();
    if (groupId.isEmpty) {
      throw ArgumentError.value(imGroupId, 'imGroupId', 'must not be empty');
    }
    final response = await http.requests.get(
      '/api/v1/agent/entry-context',
      queryParameters: <String, dynamic>{'imGroupId': groupId},
      options: Options(
        extra: const <String, dynamic>{
          SangongGameHttp.extraSkipTenant: true,
        },
      ),
    );
    return AgentEntryContextDto.fromJson(_unwrapMap(response.data));
  }

  Future<SangongTeamMembersDto> fetchSangongTeamMembers({
    bool direct = false,
    String? batchNo,
    int? sessionId,
    String? agentImUserId,
  }) async {
    final batch = batchNo?.trim() ?? '';
    final response = await http.requests.get(
      '/api/v1/me/team/members',
      queryParameters: <String, dynamic>{
        'direct': direct,
        if (agentImUserId != null && agentImUserId.trim().isNotEmpty)
          'agentImUserId': agentImUserId.trim(),
        if (batch.isNotEmpty)
          'batchNo': batch
        else if (sessionId != null && sessionId > 0)
          'sessionId': sessionId,
      },
    );
    final data = _unwrapMap(response.data);
    SangongAgentResponse.members(data);
    return SangongTeamMembersDto.fromJson(data);
  }

  Future<Map<String, dynamic>> fetchSangongTeamDashboard({
    bool direct = false,
    String? batchNo,
  }) async {
    final batch = batchNo?.trim() ?? '';
    final response = await http.requests.get(
      '/api/v1/me/team/dashboard',
      queryParameters: <String, dynamic>{
        'direct': direct,
        if (batch.isNotEmpty) 'batchNo': batch,
      },
    );
    final data = _unwrapMap(response.data);
    SangongAgentResponse.dashboard(data);
    return data;
  }

  Future<Map<String, dynamic>> fetchSangongMemberDashboard({
    required String imUserId,
  }) async {
    final id = imUserId.trim();
    if (id.isEmpty) throw ArgumentError('成员 IM 用户 ID 不能为空');
    final response = await http.requests.get(
      '/api/v1/me/team/member-dashboard',
      queryParameters: {'imUserId': id},
    );
    final data = _unwrapMap(response.data);
    SangongAgentResponse.memberDashboard(data, id);
    return data;
  }

  Future<Map<String, dynamic>> fetchSangongMemberDaily({
    required String imUserId,
    String? batchNo,
    String? from,
    String? to,
  }) async {
    final id = imUserId.trim();
    if (id.isEmpty) throw ArgumentError('成员 IM 用户 ID 不能为空');
    final response = await http.requests.get(
      '/api/v1/me/member-daily',
      queryParameters: {
        'imUserId': id,
        if (batchNo != null && batchNo.trim().isNotEmpty)
          'batchNo': batchNo.trim(),
        if (from != null && from.trim().isNotEmpty) 'from': from.trim(),
        if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
      },
    );
    final data = _unwrapMap(response.data);
    SangongAgentResponse.daily(data);
    return data;
  }

  Future<Map<String, dynamic>> transferToChild({
    required String toImUserId,
    required num amount,
    String note = '团队划转',
  }) async {
    final target = toImUserId.trim();
    if (target.isEmpty) throw ArgumentError('下级 IM 用户 ID 不能为空');
    if (!amount.isFinite || amount <= 0) throw ArgumentError('划转积分必须大于 0');
    final response = await http.requests.post(
      '/api/v1/me/transfer-to-child',
      data: <String, dynamic>{
        'toImUserId': target,
        'amount': amount,
        'note': note.trim().isEmpty ? '团队划转' : note.trim(),
      },
    );
    final result = _unwrapMap(response.data);
    final reference = result['referenceId']?.toString().trim() ?? '';
    if (reference.isEmpty ||
        SangongAgentResponse.number(result['fromBalance']) == null) {
      throw const GroupFeatureException('操作结果尚未确认，请刷新后查看',
          code: 'UNKNOWN_RESULT', unknownResult: true);
    }
    return result;
  }

  Future<Map<String, dynamic>> claimSangongRebate() async {
    final response = await http.requests.post(
      '/api/v1/me/rebate/claim',
    );
    const unknown = GroupFeatureException('返水申请结果尚未确认，请刷新后查看',
        code: 'UNKNOWN_RESULT', unknownResult: true);
    Map<String, dynamic> result;
    try {
      result = _unwrapMap(response.data);
    } on FormatException {
      throw unknown;
    }
    final amount = SangongAgentResponse.number(result['amount']);
    if (amount == null || amount < 0) {
      throw unknown;
    }
    return result;
  }
}
