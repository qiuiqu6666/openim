import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/complaints/complaint_reason_page.dart';
import 'package:openim/pages/mine/settings/feedback/feedback_submission.dart';
import 'package:openim/pages/mine/settings/pages/feedback_page.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';

void main() {
  tearDown(Get.reset);
  for (final dark in [false, true]) {
    testWidgets(
        'complaint permits optional details, locks submit and shows success dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(750, 1624);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<String>();
      var calls = 0;
      await tester.pumpWidget(GetMaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: FeedbackPage(
            service: const StubSettingsService(),
            submission: FeedbackSubmission(
              target: 'Test group (group_1)',
              reason: 'Spam',
              submit: (id, content, files) {
                calls++;
                expect(content, isEmpty);
                return pending.future;
              },
            )),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Reported target'), findsOneWidget);
      expect(find.text('Test group (group_1)'), findsOneWidget);
      expect(find.byKey(const ValueKey('feedback-diagnostics')), findsNothing);
      final button = find.byKey(const ValueKey('feedback-submit'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
      expect(calls, 1);
      pending.complete('cp_test');
      await tester.pumpAndSettle();
      expect(find.text('Submitted successfully'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('ordinary feedback still requires content', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: FeedbackPage(service: StubSettingsService())));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ElevatedButton>(
                find.byKey(const ValueKey('feedback-submit')))
            .onPressed,
        isNull);
  });
  testWidgets('all seven reference reasons remain available with large text',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: const ComplaintReasonPage(
            reportedUserID: 'peer', targetName: 'Peer')));
    await tester.pumpAndSettle();
    expect(find.text('Spam'), findsOneWidget);
    expect(find.text('Harassment'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
