import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/auth/feedback/auth_notice.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(GetMaterialApp(
      home: const Scaffold(body: Text('Authentication')),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('duplicate notices share one dialog and dismissal permits retry',
      (tester) async {
    await mount(tester);
    unawaited(showAuthNotice('First failure'));
    unawaited(showAuthNotice('Duplicate failure'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('First failure'), findsOneWidget);
    expect(find.text('Duplicate failure'), findsNothing);
    await tester.tap(find.byType(CupertinoDialogAction));
    await tester.pumpAndSettle();
    unawaited(showAuthNotice('Retry failure'));
    await tester.pumpAndSettle();
    expect(find.text('Retry failure'), findsOneWidget);
    await tester.tap(find.byType(CupertinoDialogAction));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'disposing the old navigator cannot suppress a new session notice',
      (tester) async {
    await mount(tester);
    unawaited(showAuthNotice('Old session failure'));
    await tester.pumpAndSettle();
    expect(find.text('Old session failure'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    Get.reset();
    Get.testMode = true;
    await mount(tester);
    unawaited(showAuthNotice('New session failure'));
    await tester.pumpAndSettle();
    expect(find.text('New session failure'), findsOneWidget);
    expect(find.text('Old session failure'), findsNothing);
    await tester.tap(find.byType(CupertinoDialogAction));
    await tester.pumpAndSettle();
  });
}
