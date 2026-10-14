import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../controller/im_controller.dart';
import '../im_callback.dart';
import '../youmeng/youmeng_runtime.dart';
import '../user_activity/activity_runtime.dart';
import 'manual_node_switch_service.dart';
import 'node_endpoint.dart';
import 'startup_node_selection.dart';
import 'route_history.dart';

/// One coordinator for all node pages, reusing the existing SDK session owner.
class ManualNodeSwitchRuntime {
  static final instance = ManualNodeSwitchService(
    readSession: () {
      final user = DataSp.userID;
      final token = DataSp.imToken;
      if (user == null || user.isEmpty || token == null || token.isEmpty) {
        return null;
      }
      return (user, token, DataSp.chatToken);
    },
    canSwitch: () =>
        Get.isRegistered<IMController>() && !Get.find<IMController>().isBusy,
    connect: reconnect,
  );

  static Future<void> reconnect(
      NodeEndpoint node, bool Function() sameSession) async {
    void checkSession() {
      if (!sameSession()) throw NodeSwitchFailure.sessionChanged;
    }

    checkSession();
    final logic = Get.find<IMController>();
    final user = DataSp.userID!;
    final token = DataSp.imToken!;
    if (Logger().sdkIsInited) await logic.logout();
    checkSession();
    if (node.signature == NodeEndpoint.shield.signature) {
      YoumengRuntime.applyShieldRoute();
    } else {
      await StartupNodeSelector.persist(node);
      Config.useRuntimeNetworkRoute(null);
    }
    checkSession();
    dio.options.baseUrl = node.imApi;

    // This SDK's unInitSDK intentionally returns void (native sends no reply).
    // The following init uses the same FIFO method channel, after native teardown.
    OpenIM.iMManager.unInitSDK();
    Logger().sdkIsInited = false;
    if (!await logic.initOpenIM(notifyStartup: false)) {
      throw NodeSwitchFailure.connectionFailed;
    }
    checkSession();
    final connected = Completer<bool>();
    final subscription = logic.imSdkStatusPublishSubject.listen((event) {
      if (connected.isCompleted) return;
      if (event.status == IMSdkStatus.connectionSucceeded ||
          event.status == IMSdkStatus.syncEnded) {
        connected.complete(true);
      } else if (event.status == IMSdkStatus.connectionFailed) {
        connected.complete(false);
      }
    });
    try {
      await logic.login(user, token);
      checkSession();
      if (!await connected.future
          .timeout(const Duration(seconds: 15), onTimeout: () => false)) {
        throw NodeSwitchFailure.connectionFailed;
      }
      checkSession();
      ActivityRuntime.instance.sessionRestored(user, token);
      await RouteHistory.remember(node);
    } finally {
      await subscription.cancel();
    }
  }
}
