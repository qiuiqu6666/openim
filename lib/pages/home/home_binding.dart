import 'package:get/get.dart';
import '../../core/contacts/contact_remark_source.dart';

import '../contacts/contacts_logic.dart';
import '../conversation/conversation_logic.dart';
import '../mine/mine_logic.dart';
import 'home_logic.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => HomeLogic());
    Get.lazyPut(() => ConversationLogic());
    Get.lazyPut(() => ContactsLogic(), fenix: true);
    Get.lazyPut<ContactRemarkSource>(() => Get.find<ContactsLogic>(),
        fenix: true);
    Get.lazyPut(() => MineLogic());
  }
}
