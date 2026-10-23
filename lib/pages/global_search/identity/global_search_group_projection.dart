import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Live SDK events win over search snapshots, including late query responses.
class GlobalSearchGroupProjection {
  final _changed = <String, GroupInfo>{};
  final _removed = <String>{};

  void update(GroupInfo group) {
    if (_removed.contains(group.groupID)) return;
    final previous = _changed[group.groupID];
    _changed[group.groupID] = GroupInfo.fromJson({
      ...?previous?.toJson(),
      for (final entry in group.toJson().entries)
        if (entry.value != null) entry.key: entry.value,
    });
  }

  void join(GroupInfo group) {
    _removed.remove(group.groupID);
    update(group);
  }

  void remove(String id) {
    _removed.add(id);
    _changed.remove(id);
  }

  bool hasChanged(String? id) => _changed.containsKey(id);

  GroupInfo resolve(GroupInfo group) => GroupInfo.fromJson({
        ...group.toJson(),
        for (final entry in (_changed[group.groupID]?.toJson() ?? {}).entries)
          if (entry.value != null) entry.key: entry.value,
      });

  List<GroupInfo> project(Iterable<GroupInfo> groups, String query) {
    final key = query.toLowerCase();
    return {
      for (final original in groups)
        if (!_removed.contains(original.groupID))
          original.groupID: resolve(original),
    }
        .values
        .where((group) =>
            group.status != 2 &&
            (!hasChanged(group.groupID) ||
                group.groupID.toLowerCase().contains(key) ||
                (group.groupName?.toLowerCase().contains(key) ?? false)))
        .toList();
  }
}
