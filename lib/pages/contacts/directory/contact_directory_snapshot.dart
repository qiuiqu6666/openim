import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../contacts_logic.dart';
import 'contact_directory_indexer.dart';

/// Pickers share the account owner's indexed directory. Standalone routes use
/// bounded SDK pages and the same worker, never a 10,000-name UI-isolate sort.
Future<List<ISUserInfo>> loadContactDirectorySnapshot() async {
  if (Get.isRegistered<ContactsLogic>()) {
    final owner = Get.find<ContactsLogic>();
    if (owner.isCurrentSession) {
      if (owner.friends.isEmpty) await owner.ensureFriendsLoaded();
      if (!owner.isCurrentSession) return [];
      return owner.friends.toList(growable: false);
    }
  }
  final account = DataSp.userID;
  final token = DataSp.chatToken;
  bool current() => account == DataSp.userID && token == DataSp.chatToken;
  final users = <String, ISUserInfo>{};
  for (var offset = 0; current(); offset += 1000) {
    final page = await OpenIM.iMManager.friendshipManager.getFriendListPage(
      offset: offset,
      count: 1000,
      filterBlack: true,
    );
    if (!current()) return [];
    for (final friend in page) {
      if (friend.userID != null) {
        users[friend.userID!] = ISUserInfo.fromJson(friend.toJson());
      }
    }
    if (page.length < 1000) break;
  }
  final indexer = ContactDirectoryIndexer();
  try {
    final indexed = await indexer.build([
      for (final user in users.values)
        ContactNameIndex(userID: user.userID!, displayName: user.showName),
    ]);
    if (!current()) return [];
    return [
      for (final name in indexed ?? <ContactNameIndex>[])
        users[name.userID]!
          ..tagIndex = name.tagIndex
          ..namePinyin = name.namePinyin
          ..isShowSuspension = name.showHeader,
    ];
  } finally {
    indexer.close();
  }
}
