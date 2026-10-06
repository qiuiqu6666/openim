import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'group_member_identity_info.dart';

class GroupMemberIdentityVersion {
  const GroupMemberIdentityVersion({
    required this.groupID,
    this.versionID = '',
    this.version = 0,
  });

  final String groupID;
  final String versionID;
  final int version;

  Map<String, dynamic> toJson() => {
        'groupID': groupID,
        'versionID': versionID,
        'version': version,
      };
}

/// Insert and update use the same permission-scoped account contract as lists.
class GroupMemberIdentityIncremental {
  GroupMemberIdentityIncremental.fromJson(Map<String, dynamic> json)
      : version = _number(json['version']),
        versionID = _string(json['versionID']),
        full = json['full'] == true,
        delete = _deleted(json['delete']),
        insert = parseGroupMemberIdentities(json['insert']),
        update = parseGroupMemberIdentities(json['update']),
        group = json['group'] == null
            ? null
            : GroupInfo.fromJson(_map(json['group'])),
        sortVersion = _number(json['sortVersion']);

  final int version;
  final String versionID;
  final bool full;
  final List<String> delete;
  final List<GroupMemberIdentityInfo> insert;
  final List<GroupMemberIdentityInfo> update;
  final GroupInfo? group;
  final int sortVersion;

  static int _number(Object? value) {
    if (value == null) return 0;
    final parsed = value is int
        ? value
        : value is String
            ? int.tryParse(value)
            : null;
    if (parsed == null || parsed < 0) {
      throw const FormatException('Invalid group member version');
    }
    return parsed;
  }

  static String _string(Object? value) {
    if (value == null) return '';
    if (value is! String) {
      throw const FormatException('Invalid group member version ID');
    }
    return value;
  }

  static List<String> _deleted(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.any((id) => id is! String)) {
      throw const FormatException('Invalid deleted group members');
    }
    return List<String>.unmodifiable(value.cast<String>());
  }
}

List<GroupMemberIdentityInfo> parseGroupMemberIdentities(Object? value) {
  if (value == null) return const [];
  if (value is! List) {
    throw const FormatException('Invalid group member list');
  }
  return List<GroupMemberIdentityInfo>.unmodifiable(value.map(
    (member) => GroupMemberIdentityInfo.fromJson(_map(member)),
  ));
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) {
    throw const FormatException('Invalid group member response');
  }
  return Map<String, dynamic>.from(value);
}
