// Adapted from 99chat d7c3c65, Apache-2.0.
import '../../data/group_feature_api.dart';
import '../models/agent_rebate_models.dart';
import 'sangong_game_http.dart';
import 'sangong_agent_response.dart';
import 'sangong_v2_api.dart';

class AgentRebateApi {
  AgentRebateApi(this.http) : _api = SangongV2Api(http, agent: true);
  final SangongGameHttp http;
  final SangongV2Api _api;

  Future<AgentEntryContextDto> fetchEntryContext(String imGroupId) async {
    if (imGroupId.trim() != http.context.groupID) {
      throw ArgumentError('代理群与当前页面不一致');
    }
    final data = await _api.read('context', binding: true);
    final agent = data['agent'];
    if (data['agentImGroupId'] != imGroupId.trim() ||
        data['agentImUserId'] != http.context.currentUserID ||
        data['tenantId'] is! String ||
        agent is! Map ||
        SangongAgentResponse.number(agent['balance']) == null) {
      throw const FormatException('代理身份或绑定数据无效');
    }
    return AgentEntryContextDto.fromJson(data);
  }

  Future<SangongTeamMembersDto> fetchSangongTeamMembers({
    bool direct = false,
    String? batchNo,
    int? sessionId,
    String? agentImUserId,
  }) async {
    final batch = batchNo?.trim() ?? '';
    final data = await _api.team('team', {
      'direct': direct,
      if (agentImUserId?.trim().isNotEmpty == true)
        'imUserId': agentImUserId!.trim(),
      if (batch.isNotEmpty)
        'batchNo': batch
      else if (sessionId != null && sessionId > 0)
        'sessionId': sessionId,
    });
    SangongAgentResponse.members(data);
    return SangongTeamMembersDto.fromJson(data);
  }

  Future<Map<String, dynamic>> fetchSangongTeamDashboard({
    bool direct = false,
    String? batchNo,
  }) async {
    final data = await _api.team('team-summary', {
      'direct': direct,
      if (batchNo?.trim().isNotEmpty == true) 'batchNo': batchNo!.trim(),
    });
    SangongAgentResponse.dashboard(data);
    return data;
  }

  Future<Map<String, dynamic>> fetchSangongMemberDashboard({
    required String imUserId,
  }) async {
    final id = imUserId.trim();
    if (id.isEmpty) throw ArgumentError('成员 IM 用户 ID 不能为空');
    final data = await _api.read('member', query: {'imUserId': id});
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
    final data = await _api.read('member-daily', query: {
      'imUserId': id,
      if (batchNo?.trim().isNotEmpty == true) 'batchNo': batchNo!.trim(),
      if (from?.trim().isNotEmpty == true) 'from': from!.trim(),
      if (to?.trim().isNotEmpty == true) 'to': to!.trim(),
    });
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
    if (!amount.isFinite || amount <= 0 || amount != amount.round()) {
      throw ArgumentError('划转积分必须为正整数');
    }
    final result = await _api.command('agent.transfer', {
      'imUserId': target,
      'amount': amount.toInt(),
    });
    if (result['referenceId']?.toString().isNotEmpty != true ||
        SangongAgentResponse.number(result['fromBalance']) == null) {
      throw const GroupFeatureException('操作结果尚未确认，请刷新后查看',
          code: 'UNKNOWN_RESULT', unknownResult: true);
    }
    return result;
  }

  Future<Map<String, dynamic>> claimSangongRebate() async {
    final result = await _api.command('rebate.claim', const {});
    final amount = SangongAgentResponse.number(result['amount']);
    if (amount == null || amount < 0) {
      throw const GroupFeatureException('返水申请结果尚未确认，请刷新后查看',
          code: 'UNKNOWN_RESULT', unknownResult: true);
    }
    return result;
  }
}
