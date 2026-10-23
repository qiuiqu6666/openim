import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';

typedef ProfileExtensionLoader = Future<String> Function(
    String userID, String server, String token);

/// The SDK's getUsersInfo also reads its process cache. Profile detail needs
/// an authoritative extension because FriendInfo.ex is relationship metadata.
class ProfileExtensionSource {
  static Future<String> load(String userID, String server, String token) async {
    final data = await HttpUtil.post(
      '${server.replaceFirst(RegExp(r'/+$'), '')}/user/get_users_info',
      data: {
        'userIDs': [userID]
      },
      options: Options(headers: {'token': token}),
      showErrorToast: false,
    );
    final users = data is Map ? data['usersInfo'] : null;
    if (users is List) {
      for (final user in users) {
        if (user is Map && user['userID'] == userID) {
          final ex = user['ex'];
          // Protobuf JSON may omit an empty extension (signature cleared).
          if (ex == null) return '';
          if (ex is String) return ex;
        }
      }
    }
    throw const FormatException('Profile extension unavailable');
  }
}
