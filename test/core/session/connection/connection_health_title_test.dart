import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/core/session/connection/widgets/connection_health_title.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';

void main() {
  testWidgets('route marker updates and failure replaces stale latency',
      (tester) async {
    var route = NodeEndpoint.direct;
    final api = ValueNotifier<bool?>(true);
    final latency = ValueNotifier<int?>(128);
    addTearDown(api.dispose);
    addTearDown(latency.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConnectionHealthTitle(
                title: 'Messages',
                connection: IMSdkStatus.connectionSucceeded,
                apiAvailable: api,
                latencyMs: latency,
                routeMarker: () => route.diagnosticCode))));
    expect(find.text('128 ms · 1'), findsOneWidget);
    route = NodeEndpoint.backup;
    Config.networkRouteRevision.value++;
    await tester.pump();
    expect(find.text('128 ms · 2'), findsOneWidget);
    route = NodeEndpoint.shield;
    api.value = false;
    await tester.pump();
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
  });
  for (final brightness in Brightness.values) {
    testWidgets('latency updates and hides stale values in $brightness',
        (tester) async {
      final api = ValueNotifier<bool?>(true);
      final latency = ValueNotifier<int?>(128);
      addTearDown(api.dispose);
      addTearDown(latency.dispose);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
              body: SizedBox(
                  width: 180,
                  child: ConnectionHealthTitle(
                      title: 'Messages',
                      connection: IMSdkStatus.connectionSucceeded,
                      apiAvailable: api,
                      latencyMs: latency)))));
      expect(find.text('128 ms'), findsOneWidget);
      latency.value = 86;
      await tester.pump();
      expect(find.text('86 ms'), findsOneWidget);
      expect(find.text('128 ms'), findsNothing);
      api.value = false;
      await tester.pump();
      expect(find.text('86 ms'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('normal title requires API and SDK; either failure is shown',
      (tester) async {
    final api = ValueNotifier<bool?>(null);
    addTearDown(api.dispose);
    Future<void> mount(IMSdkStatus status) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ConnectionHealthTitle(
                title: 'Messages', connection: status, apiAvailable: api))));
    await mount(IMSdkStatus.connectionSucceeded);
    expect(find.byType(FadingArcSpinner), findsOneWidget);
    api.value = true;
    await tester.pump();
    expect(find.text('Messages'), findsOneWidget);
    api.value = false;
    await tester.pump();
    expect(find.text('Service unavailable'), findsOneWidget);
    api.value = true;
    await mount(IMSdkStatus.connectionFailed);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text('Messages'), findsNothing);
    await mount(IMSdkStatus.connectionSucceeded);
    expect(find.text('Messages'), findsOneWidget);
  });
}
