import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/legacy_identity/legacy_group_identity.dart';

/// Contact transports leave lifecycle and error policy to the search owner.
class ContactSearchSource {
  Future<List<UserFullInfo>?> users(String keyword, int page,
      {int? way}) async {
    final account = normalizePublicAccountSearch(keyword);
    final searchWay = way ??
        (account != null
            ? null
            : keyword.contains('@') && !keyword.startsWith('@')
                ? 3
                : RegExp(r'^\+?\d+$').hasMatch(keyword)
                    ? 2
                    : null);
    final data = await _post('${Config.appAuthUrl}/user/search/full', {
      'pagination': {'pageNumber': page, 'showNumber': 20},
      'keyword': keyword,
      if (searchWay != null) 'way': searchWay,
    });
    if (data is! Map || data['users'] is! List) return null;
    return (data['users'] as List)
        .map((user) =>
            UserFullInfo.fromJson(Map<String, dynamic>.from(user as Map)))
        .toList();
  }

  Future<List<FriendInfo>> friends(String keyword) async {
    final data = await _post(Urls.searchFriendInfo, {
      'pagination': {'pageNumber': 1, 'showNumber': 10},
      'keyword': keyword,
    });
    if (data is! Map || data['users'] is! List) return [];
    return (data['users'] as List)
        .map((user) =>
            FriendInfo.fromJson(Map<String, dynamic>.from(user as Map)))
        .toList();
  }

  Future<dynamic> _post(String url, Map<String, dynamic> data) => HttpUtil.post(
        url,
        data: data,
        showErrorToast: false,
        options: Options(headers: {'token': DataSp.chatToken}),
      );

  Future<List<GroupInfo>> groups(String keyword) =>
      OpenIM.iMManager.groupManager
          .getGroupsInfo(groupIDList: [LegacyGroupIdentity.canonical(keyword)]);
}
