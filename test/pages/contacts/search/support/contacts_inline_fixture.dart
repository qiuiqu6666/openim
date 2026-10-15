import 'package:get/get.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/presence_store.dart';
import 'package:openim/pages/contacts/star_friend_store.dart';
import 'package:openim_common/openim_common.dart';

class InlineContactsFixture extends GetxController implements ContactsLogic {
  InlineContactsFixture({int count = 0}) {
    friends.assignAll(List.generate(
        count,
        (index) => IMUtils.setAzPinyinAndTag(ISUserInfo.fromJson({
              'userID': 'contact-$index',
              'nickname': '联系人 $index',
            })) as ISUserInfo));
  }

  @override
  final friends = <ISUserInfo>[].obs;
  @override
  final friendsLoading = false.obs;
  @override
  final friendsLoadFailed = false.obs;
  @override
  final presence = PresenceStore();
  @override
  final stars = StarFriendStore();
  @override
  int get friendApplicationCount => 0;
  @override
  int get groupApplicationCount => 0;
  int legacySearches = 0;

  @override
  void searchContacts() => legacySearches++;
  @override
  void searchAddContacts() {}
  @override
  void createContactsGroup() {}
  @override
  Future<void> scanContacts() async {}
  @override
  void newFriend() {}
  @override
  void newGroup() {}
  @override
  void myGroup() {}
  @override
  void viewFriend(ISUserInfo friend) {}
  @override
  void setPresenceVisible(String id, bool visible) {}

  @override
  void onClose() {
    presence.dispose();
    stars.dispose();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
