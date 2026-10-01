import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../group_requests_logic.dart';

class ProcessGroupRequestsLogic extends GetxController {
  final groupRequestsLogic = Get.find<GroupRequestsLogic>();
  late GroupApplicationInfo applicationInfo;
  final handleResult = 0.obs;
  bool _processing = false;

  @override
  void onInit() {
    applicationInfo = Get.arguments['applicationInfo'];
    handleResult.value = applicationInfo.handleResult ?? 0;
    super.onInit();
  }

  bool get isInvite => groupRequestsLogic.isInvite(applicationInfo);

  String get groupName => groupRequestsLogic.getGroupName(applicationInfo);

  String get inviterNickname => groupRequestsLogic.getInviterNickname(applicationInfo);

  GroupMembersInfo? getMemberInfo(inviterUserID) => groupRequestsLogic.getMemberInfo(inviterUserID);

  UserInfo? getUserInfo(inviterUserID) => groupRequestsLogic.getUserInfo(inviterUserID);

  String get sourceFrom {
    if (applicationInfo.joinSource == 2) {
      return '$inviterNickname${StrRes.byMemberInvite}';
    } else if (applicationInfo.joinSource == 4) {
      return StrRes.byScanQrcode;
    }
    return StrRes.bySearch;
  }

  void approve() {
    if (_processing || handleResult.value != 0) return;
    _processing = true;
    LoadingView.singleton
        .wrap(
            asyncFunction: () => OpenIM.iMManager.groupManager.acceptGroupApplication(
                  groupID: applicationInfo.groupID!,
                  userID: applicationInfo.userID!,
                  handleMsg: "reason",
                ))
        .then((value) => _setResult(1))
        .catchError(_parse)
        .whenComplete(() => _processing = false);
  }

  void reject() {
    if (_processing || handleResult.value != 0) return;
    _processing = true;
    LoadingView.singleton
        .wrap(
            asyncFunction: () => OpenIM.iMManager.groupManager.refuseGroupApplication(
                  groupID: applicationInfo.groupID!,
                  userID: applicationInfo.userID!,
                  handleMsg: "reason",
                ))
        .then((value) => _setResult(-1))
        .catchError(_parse)
        .catchError((_) => IMViews.showToast(StrRes.rejectFailed))
        .whenComplete(() => _processing = false);
  }

  void _setResult(int result) {
    applicationInfo.handleResult = result;
    handleResult.value = result;
    for (final item in groupRequestsLogic.list) {
      if (item.groupID == applicationInfo.groupID &&
          item.userID == applicationInfo.userID &&
          item.reqTime == applicationInfo.reqTime) {
        item.handleResult = result;
      }
    }
    groupRequestsLogic.list.refresh();
    groupRequestsLogic.homeLogic.getUnhandledGroupApplicationCount();
  }

  Future<void> _parse(dynamic e) async {
    if (e is PlatformException) {
      if (e.code == '${SDKErrorCode.groupApplicationHasBeenProcessed}') {
        IMViews.showToast(StrRes.groupRequestHandled);
        await groupRequestsLogic.getApplicationList();
        final updated = groupRequestsLogic.list.firstWhereOrNull((item) =>
            item.groupID == applicationInfo.groupID &&
            item.userID == applicationInfo.userID &&
            item.reqTime == applicationInfo.reqTime);
        if (updated?.handleResult != null && updated!.handleResult != 0) {
          _setResult(updated.handleResult!);
        }
        return;
      }
    }
    IMViews.showToast(e.toString());
  }
}
