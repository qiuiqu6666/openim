import '../../../data/group_feature_api.dart';
import '../../api/sangong_game_http.dart';
import '../../api/sangong_v2_api.dart';

/// Percentages remain decimal strings until the Go engine parses fixed units.
String sangongRebateRate(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d{1,3}(\.\d{1,4})?$').hasMatch(value)) {
    throw StateError('返水比例须为 0–100，最多四位小数');
  }
  final parts = value.split('.');
  final units = int.parse(parts[0]) * 10000 +
      int.parse((parts.length == 2 ? parts[1] : '').padRight(4, '0'));
  if (units > 1000000) throw StateError('返水比例不能超过 100%');
  return '${units ~/ 10000}.${(units % 10000).toString().padLeft(4, '0')}';
}

class SangongAgentManagementApi {
  SangongAgentManagementApi(this.http, {this.agent = false})
      : _api = SangongV2Api(http, agent: agent);
  final SangongGameHttp http;
  final bool agent;
  final SangongV2Api _api;

  Future<List<String>> groups() async {
    final data = await _api.read('agent-groups');
    final groups = data['agentGroupIds'];
    if (data['gameGroupId'] != http.context.groupID ||
        groups is! List ||
        groups.any((id) => id is! String || id.trim().isEmpty)) {
      throw const FormatException('代理群绑定数据无效');
    }
    return List<String>.from(groups);
  }

  Future<void> bind(String groupId) async {
    final id = groupId.trim();
    if (id.isEmpty || id == http.context.groupID) {
      throw StateError('请填写独立代理群的群 ID');
    }
    final data = await _api.command('agent.group_bind', {'agentGroupId': id});
    if (data['agentGroupId'] != id ||
        data['gameGroupId'] != http.context.groupID ||
        data['tenantId'] != http.tenantId) {
      throw _unknown;
    }
  }

  Future<String?> userGroup(String imUserId) async {
    final data =
        await _api.read('user-agent-group', query: {'imUserId': imUserId});
    return _readUserGroup(data, imUserId);
  }

  Future<void> setUserGroup(String imUserId, String? groupId) async {
    final id = groupId?.trim();
    if (id != null &&
        (id.isEmpty ||
            id.length > 128 ||
            RegExp(r'[\x00-\x1f\x7f/\\%;]').hasMatch(id))) {
      throw StateError('请填写有效的群 ID');
    }
    final data = await _api.command('user.agent_group', {
      'imUserId': imUserId,
      'agentGroupId': id ?? '',
    });
    if (_readUserGroup(data, imUserId) != id) throw _unknown;
  }

  String? _readUserGroup(Map<String, dynamic> data, String imUserId) {
    if (data['imUserId'] != imUserId ||
        data['gameGroupId'] != http.context.groupID ||
        !data.containsKey('agentGroupId') ||
        (data['agentGroupId'] != null &&
            (data['agentGroupId'] is! String ||
                (data['agentGroupId'] as String).isEmpty))) {
      throw _unknown;
    }
    return data['agentGroupId'] as String?;
  }

  Future<void> attach(int userId, int parentId) async {
    if (userId <= 0 || parentId <= 0 || userId == parentId) {
      throw StateError('上级用户无效');
    }
    final data = await _api
        .command('agent.attach', {'userId': userId, 'parentUserId': parentId});
    if (data['userId'] != userId || data['parentUserId'] != parentId) {
      throw _unknown;
    }
  }

  Future<void> setRate(int userId, String input) async {
    if (userId <= 0) throw StateError('成员资料尚未确认，请刷新');
    final rate = sangongRebateRate(input);
    final data = await _api.command(agent ? 'agent.rate' : 'admin.rebate_rate',
        {'userId': userId, 'rate': rate});
    if (data['userId'] != userId || data['rate'] != rate) throw _unknown;
  }

  static const _unknown = GroupFeatureException('操作结果尚未确认，请刷新后查看',
      code: 'UNKNOWN_RESULT', unknownResult: true);
}
