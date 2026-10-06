import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';

/// A background refresh never clears credentials or navigates on its own.
/// The owning session decides whether an authentication failure is current.
class CurrentUserProfileSource {
  Future<UserFullInfo?> fetch(String account, String? token,
      {String? baseUrl}) async {
    if (account.trim().isEmpty || token?.trim().isNotEmpty != true) return null;
    final base =
        (baseUrl ?? Config.appAuthUrl).trim().replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty) return null;
    final data = await HttpUtil.post(
      '$base/user/find/full',
      showErrorToast: false,
      data: {
        'pagination': {'pageNumber': 0, 'showNumber': 10},
        'userIDs': [account],
        'platform': IMUtils.getPlatform(),
      },
      options: Options(headers: {'token': token}),
    );
    if (data is! Map || data['users'] is! List) return null;
    final users = (data['users'] as List).whereType<Map>();
    for (final value in users) {
      final user = UserFullInfo.fromJson(Map<String, dynamic>.from(value));
      if (user.userID == account) return user;
    }
    return null;
  }
}
