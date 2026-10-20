import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class ProcessFriendRequestsLogic extends GetxController {
  late FriendApplicationInfo applicationInfo;
  final processing = false.obs;

  @override
  void onInit() {
    applicationInfo = Get.arguments['applicationInfo'];
    super.onInit();
  }

  Future<void> acceptFriendApplication() => _process(true);

  Future<void> refuseFriendApplication() => _process(false);

  Future<void> _process(bool accept) async {
    if (isClosed ||
        processing.value ||
        applicationInfo.handleResult == 1 ||
        applicationInfo.handleResult == -1) {
      return;
    }
    final account = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    bool current() =>
        !isClosed &&
        account == OpenIM.iMManager.userID &&
        token == DataSp.chatToken;
    processing.value = true;
    try {
      final manager = OpenIM.iMManager.friendshipManager;
      if (accept) {
        await FriendRelationshipGuard.requireNotBlocked(
            applicationInfo.fromUserID!);
        if (!current()) return;
        await manager.acceptFriendApplication(
            userID: applicationInfo.fromUserID!);
      } else {
        await manager.refuseFriendApplication(
            userID: applicationInfo.fromUserID!);
      }
      if (!current()) return;
      applicationInfo.handleResult = accept ? 1 : -1;
      IMViews.showToast(
          accept ? StrRes.addSuccessfully : StrRes.rejectSuccessfully);
      Get.back(result: applicationInfo.handleResult);
    } catch (error) {
      if (current()) {
        IMViews.showToast(
            friendAddErrorMessage(error,
                    chinese: Get.locale?.languageCode != 'en') ??
                (accept ? StrRes.addFailed : StrRes.rejectFailed));
      }
    } finally {
      if (!isClosed) processing.value = false;
    }
  }
}
