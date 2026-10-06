import 'package:azlistview/azlistview.dart';
import 'package:openim_common/openim_common.dart';

import '../selection/contact_selection_policy.dart';

/// Makes a view projection so filtering cannot change the SDK list's headers.
List<ISUserInfo> buildContactCardFriendDirectory(
  Iterable<ISUserInfo> source, {
  String query = '',
  Map<String, int> starredAt = const {},
}) {
  final keyword = query.trim().toLowerCase();
  final starred = <ISUserInfo>[];
  final regular = <ISUserInfo>[];
  final order = <String, int>{};
  for (final friend in source) {
    if (!ContactSelectionPolicy.allows(friend)) continue;
    final id = friend.userID ?? '';
    if (id.trim().isEmpty || order.containsKey(id)) continue;
    order[id] = order.length;
    if (keyword.isNotEmpty &&
        ![
          friend.showName,
          friend.nickname,
          friend.userID,
          friend.namePinyin,
          friend.pinyin,
          friend.shortPinyin,
        ].any((value) => value?.toLowerCase().contains(keyword) == true)) {
      continue;
    }
    final copy = ISUserInfo.fromJson(friend.toJson());
    if (copy.tagIndex?.isNotEmpty != true) {
      IMUtils.setAzPinyinAndTag(copy);
    }
    if (starredAt.containsKey(id)) {
      copy.tagIndex = '★';
      starred.add(copy);
    } else {
      regular.add(copy);
    }
  }
  starred.sort((a, b) {
    final byDate = starredAt[b.userID]!.compareTo(starredAt[a.userID]!);
    return byDate != 0 ? byDate : order[a.userID]!.compareTo(order[b.userID]!);
  });
  regular.sort((a, b) {
    final aTag = a.getSuspensionTag();
    final bTag = b.getSuspensionTag();
    final byTag = aTag == bTag
        ? 0
        : aTag == '#'
            ? 1
            : bTag == '#'
                ? -1
                : aTag.compareTo(bTag);
    return byTag != 0 ? byTag : order[a.userID]!.compareTo(order[b.userID]!);
  });
  final result = [...starred, ...regular];
  SuspensionUtil.setShowSuspensionStatus(result);
  return result;
}
