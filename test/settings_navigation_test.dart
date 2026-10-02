import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/settings_navigation.dart';
import 'package:openim/pages/mine/secondary/share_app_sheet.dart';

void main() {
  testWidgets('share sheet opens above the tab bar at the screen bottom', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: root,
      home: Scaffold(
        bottomNavigationBar: const SizedBox(height: 60, child: Text('tab bar')),
        body: Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (context) => Scaffold(body: TextButton(
            onPressed: () => ShareAppSheet.show(context),
            child: const Text('share app'),
          )),
        )),
      ),
    ));
    await tester.tap(find.text('share app'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(ShareAppSheet)).bottom, 812);
    expect(find.text('tab bar').hitTestable(), findsNothing);
    root.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('tab bar').hitTestable(), findsOneWidget);
    expect(find.text('share app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('settings covers tab navigation and returns its result', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      bottomNavigationBar: const SizedBox(height: 60, child: Text('tab bar')),
      body: Navigator(onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (context) => Scaffold(body: TextButton(
          onPressed: () async {
            result = await openSettingsPage<String>(context,
              Scaffold(body: Builder(builder: (pageContext) => TextButton(
                onPressed: () => Navigator.of(pageContext).pop('saved'),
                child: const Text('return from settings'),
              ))));
          },
          child: const Text('open settings'),
        )),
      )),
    )));
    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();
    expect(find.text('tab bar'), findsNothing);
    expect(find.text('return from settings'), findsOneWidget);
    await tester.tap(find.text('return from settings'));
    await tester.pumpAndSettle();
    expect(find.text('tab bar'), findsOneWidget);
    expect(find.text('open settings'), findsOneWidget);
    expect(result, 'saved');
  });
}
