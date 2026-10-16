import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Reads only member snapshots, never group metadata or unrelated payloads.
List<Map<String, dynamic>> groupNoticeMembers(Map<String, dynamic> detail) {
  final members = <Map<String, dynamic>>[];
  for (final key in [
    'opUser',
    'inviterUser',
    'entrantUser',
    'quitUser',
    'newGroupOwner',
    'mutedUser',
    'invitedUserList',
    'kickedUserList',
  ]) {
    final value = detail[key];
    if (value is Map<String, dynamic>) members.add(value);
    if (value is List) members.addAll(value.whereType<Map<String, dynamic>>());
  }
  return members;
}

Map<String, dynamic>? groupNoticeDetail(Message message) {
  if (message.groupID?.isNotEmpty != true) return null;
  final raw = message.notificationElem?.detail;
  if (raw == null) return null;
  try {
    final value = jsonDecode(raw);
    return value is Map<String, dynamic> ? value : null;
  } on FormatException {
    return null;
  }
}

/// A display-only copy: keep the stored event, IDs and invitation fields intact.
Message resolveGroupNoticeIdentity(
  Message message, {
  required String? Function(String) nickname,
  required String? Function(String) face,
}) {
  final detail = groupNoticeDetail(message);
  if (detail == null) return message;
  var changed = false;
  for (final member in groupNoticeMembers(detail)) {
    final id = member['userID'];
    if (id is! String || id.isEmpty) continue;
    final name = nickname(id);
    final avatar = face(id);
    if (name != null && name.isNotEmpty && member['nickname'] != name) {
      member['nickname'] = name;
      changed = true;
    }
    if (avatar != null && member['faceURL'] != avatar) {
      member['faceURL'] = avatar;
      changed = true;
    }
  }
  if (!changed) return message;
  return Message.fromJson(message.toJson())
    ..notificationElem = NotificationElem.fromJson({
      ...message.notificationElem!.toJson(),
      'detail': jsonEncode(detail),
    });
}
