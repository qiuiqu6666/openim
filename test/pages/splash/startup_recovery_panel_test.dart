import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim/core/server_nodes/startup/startup_network_preparation.dart';
import 'package:openim/core/server_nodes/startup/startup_state.dart';
import 'package:openim/pages/splash/widgets/startup_recovery_panel.dart';

class PanelNetwork extends StartupNetworkPreparation {
  PanelNetwork() : super(readCurrent: () => NodeEndpoint.direct);
  int retries = 0;
  @override
  void retry() => retries++;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('automatic recovery copy, no route choices ${brightness.name}',
        (tester) async {
      Get.locale = const Locale('en');
      await tester.binding.setSurfaceSize(const Size(320, 640));
      final network = PanelNetwork();
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: StartupRecoveryPanel(network: network)))));
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Route 1'), findsNothing);
      expect(find.text('Route 2'), findsNothing);
      expect(find.text('Protected route'), findsNothing);

      network.state.value =
          const StartupState(StartupStage.probing, showDetails: true);
      await tester.pump();
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);

      network.state.value = const StartupState(StartupStage.unavailable,
          showDetails: true, showActions: true);
      await tester.pump();
      expect(
          find.textContaining('retry automatically when the network recovers'),
          findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(tester.takeException(), isNull);

      final semantics = tester.ensureSemantics();
      expect(
          find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.liveRegion == true),
          findsOneWidget);
      semantics.dispose();
      network.onClose();
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
      Get.locale = null;
    });
  }

  testWidgets('SDK initialization failure keeps a single retry action',
      (tester) async {
    Get.locale = const Locale('en');
    final network = PanelNetwork()..sdkRecoveryVisible = true;
    network.state.value = const StartupState(StartupStage.degraded,
        showDetails: true, showActions: true);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StartupRecoveryPanel(network: network))));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Route 1'), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(network.retries, 1);
    network.onClose();
    Get.locale = null;
  });
}
