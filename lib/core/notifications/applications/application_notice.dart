import 'dart:convert';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

enum ApplicationNoticeKind { friend, group }

class ApplicationNotice {
  const ApplicationNotice(
      {required this.kind,
      required this.applicant,
      required this.createdAt,
      this.recipient = '',
      this.groupID = '',
      this.nickname = '',
      this.groupName = '',
      this.pending = true});
  final ApplicationNoticeKind kind;
  final String applicant, recipient, groupID, nickname, groupName;
  final int createdAt;
  final bool pending;
  int get seconds => createdAt > 100000000000 ? createdAt ~/ 1000 : createdAt;
  String get eventKey => jsonEncode([kind.name, applicant, groupID, seconds]);

  factory ApplicationNotice.friend(FriendApplicationInfo value) =>
      ApplicationNotice(
          kind: ApplicationNoticeKind.friend,
          applicant: value.fromUserID ?? '',
          recipient: value.toUserID ?? '',
          createdAt: value.createTime ?? 0,
          nickname: value.fromNickname ?? '',
          pending: value.handleResult == 0);
  factory ApplicationNotice.group(GroupApplicationInfo value) =>
      ApplicationNotice(
          kind: ApplicationNoticeKind.group,
          applicant: value.userID ?? '',
          groupID: value.groupID ?? '',
          createdAt: value.reqTime ?? 0,
          nickname: value.nickname ?? '',
          groupName: value.groupName ?? '',
          pending: value.handleResult == 0);
}
