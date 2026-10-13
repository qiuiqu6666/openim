import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile _panel_logic.dart';
import 'package:openim_common/openim_common.dart';

class ClosureApp extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ClosureIM extends GetxController with IMCallback implements IMController {
  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ClosureHome extends GetxController implements HomeLogic {
  @override
  final unhandledFriendApplicationCount = 0.obs;
  @override
  final unhandledGroupApplicationCount = 0.obs;
  @override
  final conversationsAtFirstPage = <ConversationInfo>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ClosureConversations extends GetxController implements ConversationLogic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ClosureConversationOwner extends ConversationLogic {
  @override
  // Native subscriptions are started explicitly by this deletion fixture.
  // ignore: must_call_super
  void onInit() {}
  @override
  void onReady() {}
}

class ClosureProfile extends GetxController implements UserProfilePanelLogic {
  @override
  final userInfo = UserFullInfo(userID: 'peer', nickname: 'Peer').obs;
  @override
  bool? get offAllWhenDelFriend => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
