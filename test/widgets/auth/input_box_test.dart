import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

class _Controller extends TextEditingController {
  _Controller({super.text});
  bool get hasActiveListeners => hasListeners;
}

Future<void> _pump(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light, double textScale = 1}) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: const Locale('en'),
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Center(
            child: SizedBox(
              width: 280,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('a compact unlabeled password keeps its accessible name and eye',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(
          tester,
          const InputBox.password(
            label: 'Password',
            filled: true,
            showLabel: false,
            minHeight: 52,
            leadingIcon: Icons.lock_outline_rounded,
          ));
      expect(find.text('Password'), findsNothing);
      expect(find.bySemanticsLabel('Password'), findsWidgets);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'my-password');
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText,
          isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('prefilled and replaced controllers update clear without leaks',
      (tester) async {
    final first = _Controller(text: 'first@example.com');
    final second = _Controller();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget input(TextEditingController controller) => InputBox.account(
          key: const ValueKey('account'),
          label: 'Email',
          code: '',
          filled: true,
          controller: controller,
        );

    await _pump(tester, input(first));
    expect(find.byTooltip('Clear'), findsOneWidget);
    await _pump(tester, input(second));
    expect(first.hasActiveListeners, isFalse);
    expect(find.byTooltip('Clear'), findsNothing);
    first.text = 'stale@example.com';
    second.text = 'current@example.com';
    await tester.pump();
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(second.text, isEmpty);
    expect(first.text, 'stale@example.com');

    await tester.pumpWidget(const SizedBox.shrink());
    expect(second.hasActiveListeners, isFalse);
    second.text = 'after unmount';
    expect(tester.takeException(), isNull);
  });

  testWidgets('account with area selection only accepts phone digits',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      InputBox.account(
        label: 'Phone',
        code: '+86',
        filled: true,
        controller: controller,
        onAreaCode: () {},
      ),
    );
    await tester.enterText(find.byType(TextField), '12a 3-45');
    expect(controller.text, '12345');
    expect(tester.widget<TextField>(find.byType(TextField)).keyboardType,
        TextInputType.phone);
  });

  testWidgets('validation, submission and autofill work in a Form',
      (tester) async {
    final formKey = GlobalKey<FormState>();
    String? submitted;
    await _pump(
      tester,
      Form(
        key: formKey,
        child: InputBox.account(
          label: 'Email',
          code: '',
          filled: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => submitted = value,
          autofillHints: const [AutofillHints.email],
          validator: (value) =>
              value == null || value.isEmpty ? 'Enter your email' : null,
        ),
      ),
    );
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Enter your email'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'hello@example.com');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, 'hello@example.com');
    expect(formKey.currentState!.validate(), isTrue);
    expect(tester.widget<TextField>(find.byType(TextField)).autofillHints,
        [AutofillHints.email]);
  });

  for (final brightness in Brightness.values) {
    testWidgets('password fits large text in $brightness', (tester) async {
      final controller = TextEditingController(text: 'my-password');
      addTearDown(controller.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          InputBox.password(
            label: 'Password',
            filled: true,
            controller: controller,
          ),
          brightness: brightness,
          textScale: 2,
        );
        expect(find.bySemanticsLabel('Password'), findsWidgets);
        expect(find.byTooltip('Clear'), findsNothing);
        final eye = find.byTooltip('Show password');
        expect(tester.getSize(eye).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(eye).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(find.byType(TextField)).height, greaterThan(56));
        await tester.tap(eye);
        await tester.pump();
        expect(tester.widget<TextField>(find.byType(TextField)).obscureText,
            isFalse);
        expect(find.byTooltip('Hide password'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('code request deduplicates, retries and counts only success',
      (tester) async {
    var request = Completer<bool>();
    var calls = 0;
    await _pump(
      tester,
      VerifyCodedButton(
        themed: true,
        seconds: 2,
        onTapCallback: () {
          calls++;
          return request.future;
        },
      ),
    );
    final button = find.byType(TextButton);
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    expect(calls, 1);
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    request.complete(false);
    await tester.pump();
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    expect(find.text('Send code'), findsOneWidget);

    request = Completer<bool>();
    await tester.tap(button);
    request.complete(true);
    await tester.pump();
    expect(calls, 2);
    expect(find.text('2s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend'), findsOneWidget);
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
  });

  testWidgets('finishing code request after disposal does not update state',
      (tester) async {
    final request = Completer<bool>();
    await _pump(
      tester,
      VerifyCodedButton(themed: true, onTapCallback: () => request.future),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    request.complete(true);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'autoStart counts down an already sent code and cancels on dispose',
      (tester) async {
    var calls = 0;
    await _pump(
      tester,
      VerifyCodedButton(
        themed: true,
        autoStart: true,
        seconds: 300,
        onTapCallback: () async {
          calls++;
          return true;
        },
      ),
    );
    expect(find.text('300s'), findsOneWidget);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    expect(calls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('299s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
