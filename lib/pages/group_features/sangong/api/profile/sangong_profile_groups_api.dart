import 'dart:convert';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../../../data/group_feature_api.dart';

/// Profile operations follow the signed-in operator's authorized game group,
/// independently of the conversation from which the profile was opened.
class SangongProfileGroupsApi {
  const SangongProfileGroupsApi(this.api);
  final GroupFeatureApi api;

  Future<List<GroupInfo>> load() async {
    final data = await api.requestData('/sangong/api/v1/admin/tenants',
        useBearerAuth: true);
    if (data is! Map || data['tenants'] is! List) {
      throw const GroupFeatureException('游戏群配置返回异常，请重试');
    }
    final groups = <String, GroupInfo>{};
    for (final row in data['tenants'] as List) {
      if (row is! Map) {
        throw const GroupFeatureException('游戏群配置返回异常，请重试');
      }
      if (row['active'] != true ||
          !const ['owner', 'admin'].contains(row['myRole'])) {
        continue;
      }
      final id = row['imGroupGameId'];
      if (id is! String || id.isEmpty) {
        throw const GroupFeatureException('游戏群配置返回异常，请重试');
      }
      groups[id] = GroupInfo.fromJson({
        'groupID': id,
        // The verified tenant list identifies this as a game group. Actual
        // configuration and mutation permissions are rechecked by the runtime.
        'ex': jsonEncode({'gameType': 1}),
        'groupName': row['name'] is String ? row['name'] : id,
      });
    }
    return groups.values.toList();
  }
}
