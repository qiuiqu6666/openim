import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

String defaultCreateGroupName(List<UserInfo> members) {
  final names = members.take(2).map((member) {
    final nickname = member.nickname?.trim() ?? '';
    return nickname.isNotEmpty ? nickname : member.userID ?? '';
  }).join('、');
  return members.length > 2 ? '$names等${members.length}人' : names;
}
