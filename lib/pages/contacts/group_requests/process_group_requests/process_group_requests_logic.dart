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

  String get inviterNickname =>
      groupRequestsLogic.getInviterNickname(applicationInfo);

  GroupApplicationInfo? get _updatedApplication =>
      groupRequestsLogic.list.firstWhereOrNull((item) =>
          item.groupID == applicationInfo.groupID &&
          item.userID == applicationInfo.userID &&
          item.reqTime == applicationInfo.reqTime);

  String? get handlerNickname => groupRequestsLogic
      .getHandlerNickname(_updatedApplication ?? applicationInfo);

  int get currentHandleResult {
    final updated = _updatedApplication?.handleResult;
    if (updated == 1 || updated == -1) return updated!;
    return handleResult.value;
  }

  GroupMembersInfo? getMemberInfo(String inviterUserID) =>
      groupRequestsLogic.getMemberInfo(inviterUserID);

  UserInfo? getUserInfo(String inviterUserID) =>
      groupRequestsLogic.getUserInfo(inviterUserID);

  String get sourceFrom {
    if (applicationInfo.joinSource == 2) {
      return '$inviterNickname${StrRes.byMemberInvite}';
    } else if (applicationInfo.joinSource == 4) {
      return StrRes.byScanQrcode;
    }
    return StrRes.bySearch;
  }

  void approve() {
    if (isClosed ||
        !groupRequestsLogic.isSessionActive ||
        _processing ||
        currentHandleResult != 0) {
      return;
    }
    _processing = true;
    LoadingView.singleton
        .wrap(asyncFunction: () async {
          if (isClosed ||
              !groupRequestsLogic.isSessionActive ||
              currentHandleResult != 0) {
            return false;
          }
          await OpenIM.iMManager.groupManager.acceptGroupApplication(
            groupID: applicationInfo.groupID!,
            userID: applicationInfo.userID!,
            handleMsg: "reason",
          );
          return true;
        })
        .then<void>((submitted) async {
          if (submitted) await _complete(1);
        })
        .catchError(_parse)
        .whenComplete(() => _processing = false);
  }

  void reject() {
    if (isClosed ||
        !groupRequestsLogic.isSessionActive ||
        _processing ||
        currentHandleResult != 0) {
      return;
    }
    _processing = true;
    LoadingView.singleton
        .wrap(asyncFunction: () async {
          if (isClosed ||
              !groupRequestsLogic.isSessionActive ||
              currentHandleResult != 0) {
            return false;
          }
          await OpenIM.iMManager.groupManager.refuseGroupApplication(
            groupID: applicationInfo.groupID!,
            userID: applicationInfo.userID!,
            handleMsg: "reason",
          );
          return true;
        })
        .then<void>((submitted) async {
          if (submitted) await _complete(-1);
        })
        .catchError(_parse)
        .catchError((Object _) {
          IMViews.showToast(StrRes.rejectFailed);
        })
        .whenComplete(() => _processing = false);
  }

  void _setResult(int result) {
    if (isClosed || !groupRequestsLogic.isSessionActive) return;
    // A local success updates the status; attribution waits for the server record.
    applicationInfo.handleUserID = null;
    applicationInfo.handleResult = result;
    handleResult.value = result;
    for (final item in groupRequestsLogic.list) {
      if (item.groupID == applicationInfo.groupID &&
          item.userID == applicationInfo.userID &&
          item.reqTime == applicationInfo.reqTime) {
        item.handleUserID = null;
        item.handleResult = result;
      }
    }
    groupRequestsLogic.list.refresh();
    groupRequestsLogic.homeLogic.getUnhandledGroupApplicationCount();
  }

  Future<void> _complete(int result) async {
    if (isClosed || !groupRequestsLogic.isSessionActive) return;
    _setResult(result);
    try {
      // Only a refreshed server record can identify the actual administrator.
      await groupRequestsLogic.getApplicationList();
      if (isClosed || !groupRequestsLogic.isSessionActive) return;
      _adoptUpdatedApplication();
    } catch (error) {
      Logger.print(
          'Group application result refresh failed: ${error.runtimeType}');
    }
  }

  void _adoptUpdatedApplication() {
    final updated = _updatedApplication;
    if (updated?.handleResult == 1 || updated?.handleResult == -1) {
      applicationInfo = updated!;
      handleResult.value = updated.handleResult!;
    } else if (updated != null &&
        (handleResult.value == 1 || handleResult.value == -1)) {
      // An older pending snapshot cannot undo a successful SDK operation.
      updated.handleResult = handleResult.value;
      updated.handleUserID = null;
      applicationInfo = updated;
      groupRequestsLogic.list.refresh();
    }
  }

  Future<void> _parse(dynamic e) async {
    if (isClosed || !groupRequestsLogic.isSessionActive) return;
    if (e is PlatformException) {
      if (e.code == '${SDKErrorCode.groupApplicationHasBeenProcessed}') {
        IMViews.showToast(StrRes.groupRequestHandled);
        await groupRequestsLogic.getApplicationList();
        if (isClosed || !groupRequestsLogic.isSessionActive) return;
        _adoptUpdatedApplication();
        return;
      }
    }
    IMViews.showToast(e.toString());
  }
}
