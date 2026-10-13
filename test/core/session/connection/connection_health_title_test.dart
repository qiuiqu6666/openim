import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/core/session/connection/widgets/connection_health_title.dart';
import 'package:openim_common/openim_common.dart';

void main() {
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
