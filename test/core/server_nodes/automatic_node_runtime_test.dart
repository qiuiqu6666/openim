import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/core/server_nodes/automatic_node_runtime.dart';
import 'package:openim/core/server_nodes/manual_node_switch_service.dart';
import 'package:openim/core/server_nodes/node_availability_probe.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends IMController {
  @override
  // Test only the route coordinator, without native SDK startup.
  // ignore: must_call_super
  void onInit() {}
  @override
  void onClose() {}
}

void main() {
  late _IM im;
  late StreamController<List<ConnectivityResult>> network;
  late AutomaticNodeRuntime runtime;
  late int checks;
  late List<NodeEndpoint> connections;
  late Future<List<NodeAvailability>> Function(List<NodeEndpoint>) probe;

  void useRoute(NodeEndpoint node) {
    Config.useRuntimeNetworkRoute(RuntimeNetworkRoute(
        authUrl: node.chatApi,
        apiUrl: node.imApi,
        wsUrl: node.imWs,
        customerServiceUrl: node.customerServiceUrl ?? node.chatApi));
  }

  List<NodeAvailability> results(List<NodeEndpoint> nodes, {int? healthy}) => [
        for (var i = 0; i < nodes.length; i++)
          NodeAvailability(nodes[i], available: i == healthy, latencyMs: 20)
      ];
  void start() {
    runtime = AutomaticNodeRuntime(
      networkChanges: network.stream,
      shieldEnabled: true,
      probeNodes: (nodes, _) {
        checks++;
        return probe(nodes);
      },
      switchService: ManualNodeSwitchService(
        readSession: () => (DataSp.userID, DataSp.imToken, DataSp.chatToken),
        canSwitch: () => true,
        probe: (node) async =>
            NodeAvailability(node, available: true, latencyMs: 10),
        connect: (node, current) async {
          connections.add(node);
          useRoute(node);
        },
      ),
    )..onInit();
  }

  setUp(() async {
    Get.testMode = true;
    Get.put<AppController>(_App());
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'user',
      'imToken': 'im-token',
      'chatToken': 'chat-token',
    }));
    im = Get.put<IMController>(_IM()) as _IM;
    network = StreamController<List<ConnectivityResult>>();
    checks = 0;
    connections = [];
    useRoute(NodeEndpoint.direct);
    probe = (nodes) async => results(nodes);
  });
  tearDown(() async {
    runtime.onClose();
    await network.close();
    await im.imSdkStatusPublishSubject.close();
    await im.imSdkStatusSubject.close();
    Config.useRuntimeNetworkRoute(null);
    Get.reset();
  });

  testWidgets('failed shield probes never restart the same SDK session',
      (tester) async {
    useRoute(NodeEndpoint.shield);
    start();
    await tester.pump(const Duration(seconds: 5));
    expect(checks, 1);
    expect(connections, isEmpty);
    for (final delay in [2, 4, 8]) {
      await tester.pump(Duration(seconds: delay));
    }
    expect(checks, 4);
    expect(connections, isEmpty);
    runtime.onClose();
  });

  testWidgets(
      'network change during old probe runs fresh check without backoff',
      (tester) async {
    final pending = Completer<List<NodeAvailability>>();
    List<NodeEndpoint>? first;
    probe = (nodes) {
      first ??= nodes;
      return checks == 1
          ? pending.future
          : Future.value(results(nodes, healthy: 0));
    };
    start();
    await tester.pump(const Duration(seconds: 5));
    network.add([ConnectivityResult.mobile]);
    await tester.pump();
    expect(checks, 1);
    pending.complete(results(first!, healthy: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(checks, 2);
    expect(connections, isEmpty,
        reason: 'Old network probe cannot switch routes.');
    runtime.onClose();
  });

  testWidgets('repeated connecting callbacks cannot bypass failure backoff',
      (tester) async {
    useRoute(NodeEndpoint.shield);
    start();
    im.imSdkStatus(IMSdkStatus.connecting);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(checks, 1);
    for (var i = 0; i < 5; i++) {
      im.imSdkStatus(IMSdkStatus.connectionFailed);
      im.imSdkStatus(IMSdkStatus.connecting);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(checks, 1);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(checks, 2);
    expect(connections, isEmpty);
    runtime.onClose();
  });

  testWidgets(
      'background cancels old decisions and resume keeps the page route',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final pending = Completer<List<NodeAvailability>>();
    List<NodeEndpoint>? first;
    probe = (nodes) {
      first ??= nodes;
      return checks == 1
          ? pending.future
          : Future.value(results(nodes, healthy: 0));
    };
    start();
    await tester.pump(const Duration(seconds: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(checks, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    pending.complete(results(first!, healthy: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(checks, 2);
    expect(connections, isEmpty);
    expect(NodeEndpoint.current().signature, NodeEndpoint.direct.signature);
    runtime.onClose();
  });

  testWidgets('renewed credentials invalidate an old route decision',
      (tester) async {
    final pending = Completer<List<NodeAvailability>>();
    List<NodeEndpoint>? first;
    probe = (nodes) {
      first = nodes;
      return pending.future;
    };
    start();
    await tester.pump(const Duration(seconds: 5));
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'user',
      'imToken': 'im-token',
      'chatToken': 'new-chat-token',
    }));
    pending.complete(results(first!, healthy: 1));
    await tester.pump();
    expect(connections, isEmpty);
    runtime.onClose();
  });

  testWidgets('available alternate route still switches automatically',
      (tester) async {
    probe = (nodes) async => results(nodes, healthy: 1);
    start();
    await tester.pump(const Duration(seconds: 5));
    expect(
        connections.map((e) => e.signature), [NodeEndpoint.backup.signature]);
    runtime.onClose();
  });
}
