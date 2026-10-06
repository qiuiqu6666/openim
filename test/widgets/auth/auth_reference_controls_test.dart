import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/widgets/auth/auth_reference.dart';

void main() {
  for (final compound in [false, true]) {
    testWidgets(
        '${compound ? 'compound' : 'single'} field reports focus, not edits, and keeps its message row stable',
        (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      final changes = <bool>[];
      String? error;
      late StateSetter update;
      const fieldKey = ValueKey('feedback-field');
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                      width: 280,
                      child: StatefulBuilder(builder: (context, setState) {
                        update = setState;
                        return compound
                            ? AuthCompoundField(
                                key: fieldKey,
                                controller: controller,
                                focusNode: focus,
                                hint: 'Phone',
                                reserveErrorSpace: true,
                                errorText: error,
                                onFocusChanged: changes.add)
                            : AuthTextField(
                                key: fieldKey,
                                controller: controller,
                                focusNode: focus,
                                hint: 'Account',
                                reserveErrorSpace: true,
                                errorText: error,
                                onFocusChanged: changes.add);
                      }))))));
      final height = tester.getSize(find.byKey(fieldKey)).height;
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '123');
      await tester.pump();
      expect(changes, [true]);
      update(() => error = 'Check this value');
      await tester.pumpAndSettle();
      expect(find.text('Check this value'), findsOneWidget);
      expect(tester.getSize(find.byKey(fieldKey)).height, height);
      focus.unfocus();
      await tester.pump();
      expect(changes, [true, false]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('large translated field and form errors wrap without clipping',
      (tester) async {
    final controller = TextEditingController(text: 'account');
    addTearDown(controller.dispose);
    const error =
        'The verification code has expired. Request a new code and try again.';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                        width: 280,
                        child: SingleChildScrollView(
                            child: Column(children: [
                          AuthTextField(
                              controller: controller,
                              hint: 'Account',
                              reserveErrorSpace: true,
                              errorText: error),
                          const AuthFormMessage(text: error),
                        ]))))))));
    expect(find.text(error), findsNWidgets(2));
    expect(tester.getSize(find.byType(TextField)).height,
        greaterThan(AuthReferenceTokens.fieldHeight));
    expect(tester.getSize(find.byType(AuthFieldMessage)).height,
        greaterThan(AuthReferenceTokens.messageHeight));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed or cancelled SMS never starts a resend cooldown',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AuthCodeAction(onSend: () async {
      calls++;
      return false;
    }))));
    final button = find.byType(TextButton);
    await tester.tap(button);
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pump();
    expect(calls, 2);
    expect(find.text('60s'), findsNothing);
  });

  testWidgets('SMS sends once while pending and counts down only on success',
      (tester) async {
    final response = Completer<bool>();
    var calls = 0;
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: AuthCodeAction(onSend: () {
      calls++;
      return response.future;
    }))));
    final button = find.byType(TextButton);
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    await tester.tap(button);
    expect(calls, 1);
    response.complete(true);
    await tester.pump();
    expect(find.text('60s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'late SMS completion after leaving the form does not create a timer',
      (tester) async {
    final response = Completer<bool>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AuthCodeAction(onSend: () => response.future))));
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    response.complete(true);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'clear action updates the caller controller and retains input focus',
      (tester) async {
    final controller = TextEditingController(text: '13800138000');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AuthCompoundField(
                controller: controller,
                focusNode: focus,
                hint: 'Phone',
                leading: AuthCountryCode(code: '+86', onTap: () {}),
                leadingWidth: 102))));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(focus.hasFocus, isTrue);
    expect(find.byIcon(Icons.cancel), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
