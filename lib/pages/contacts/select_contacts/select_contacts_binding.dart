import 'package:get/get.dart';

import 'select_contacts_logic.dart';
import 'friend_list/friend_list_logic.dart';

class SelectContactsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => SelectContactsLogic());
    if (Get.arguments?['action'] == SelAction.crateGroup ||
        Get.arguments?['action'] == SelAction.addMember ||
        Get.arguments?['action'] == SelAction.carte) {
      Get.lazyPut(() => SelectContactsFromFriendsLogic());
    }
  }
}
