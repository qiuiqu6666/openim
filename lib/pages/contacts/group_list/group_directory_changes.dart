import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Keeps SDK pushes newer than an outstanding directory query, including
/// removals and groups moving between the two ownership tabs.
class GroupDirectoryChanges {
  int revision = 0;
  final _changes =
      <String, ({int revision, GroupInfo? group, bool allowInsert})>{};
  bool isRemoved(String id) =>
      _changes.containsKey(id) && _changes[id]!.group == null;

  void record(String id, GroupInfo? group, {bool allowInsert = true}) {
    _changes[id] =
        (revision: ++revision, group: group, allowInsert: allowInsert);
  }

  GroupInfo? projectGroup(GroupInfo row) {
    final change = _changes[row.groupID];
    if (change == null) return row;
    final group = change.group;
    if (group == null) return null;
    return GroupInfo.fromJson({
      ...row.toJson(),
      for (final field in group.toJson().entries)
        if (field.value != null) field.key: field.value,
    });
  }

  List<GroupInfo> project(Iterable<GroupInfo> rows,
      {required bool created, required String owner}) {
    final byID = {for (final group in rows) group.groupID: group};
    for (final entry in _changes.entries) {
      var group = entry.value.group;
      final previous = byID[entry.key];
      if (group != null) {
        if (previous == null && !entry.value.allowInsert) continue;
        if (previous != null) {
          group = GroupInfo.fromJson({
            ...previous.toJson(),
            for (final field in group.toJson().entries)
              if (field.value != null) field.key: field.value,
          });
        }
        // Partial update events cannot guess which ownership tab gains a row.
        if (group.ownerUserID == null) continue;
      }
      if (group == null || (group.ownerUserID == owner) != created) {
        byID.remove(entry.key);
      } else {
        byID[entry.key] = group;
      }
    }
    return byID.values.toList();
  }

  void confirmedThrough(int confirmed) =>
      _changes.removeWhere((_, change) => change.revision <= confirmed);

  void clear() => _changes.clear();
}
