import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../contacts/select_contacts/contact_card/support/contact_card_picker_fixture.dart';

class ChannelContactsFixture extends ContactCardPickerContacts {
  final _friends = <ISUserInfo>[
    ISUserInfo.fromJson({
      'userID': 'channel-friend',
      'nickname': '小林',
      'tagIndex': 'X',
      'namePinyin': 'XIAOLIN'
    })
  ].obs;
  @override
  RxList<ISUserInfo> get friends => _friends;
  final _friendsLoadFailed = false.obs;
  @override
  RxBool get friendsLoadFailed => _friendsLoadFailed;
  @override
  Future<void> ensureFriendsLoaded() async {}
  @override
  void setPresenceVisible(String id, bool visible) {}
}

class _ChannelIM extends GetxController implements IMController {
  @override
  final blacklistChangedSubject = PublishSubject<BlacklistInfo>();
  @override
  void onClose() {
    blacklistChangedSubject.close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void registerChannelContactsFixture() {
  final interval = VisibilityDetectorController.instance.updateInterval;
  VisibilityDetectorController.instance.updateInterval = Duration.zero;
  addTearDown(() => VisibilityDetectorController.instance.updateInterval = interval);
  OpenIM.iMManager.userID = 'self';
  OpenIM.iMManager.userInfo = UserInfo(userID: 'self');
  if (!Get.isRegistered<IMController>()) Get.put<IMController>(_ChannelIM());
  if (!Get.isRegistered<ContactsLogic>()) {
    Get.put<ContactsLogic>(ChannelContactsFixture());
  }
}
