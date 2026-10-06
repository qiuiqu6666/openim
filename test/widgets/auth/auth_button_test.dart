import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

const _enabledStyle = TextStyle(fontSize: 16, color: Color(0xFF123456));
const _disabledStyle = TextStyle(
  fontSize: 15,
  color: Color(0xFF654321),
  fontWeight: FontWeight.w500,
);

Future<void> _pump(WidgetTester tester, Widget child,
    {double textScale = 1}) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Center(child: SizedBox(width: 320, child: child)),
    ),
  ));
}

Finder get _buttonSemantics => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.button == true,
    );

void main() {
  testWidgets('a gradient button preserves disabled and loading interaction',
      (tester) async {
    var calls = 0;
    const gradient = LinearGradient(colors: [Colors.lightBlue, Colors.blue]);
    for (final state in [
      (enabled: true, loading: false),
      (enabled: false, loading: false),
      (enabled: true, loading: true)
    ]) {
      await _pump(
          tester,
          Button(
            text: 'Sign in',
            height: 52,
            gradient: gradient,
            radius: AppTokens.rLg,
            trailingIcon: Icons.arrow_forward_rounded,
            textStyle: _enabledStyle,
            enabled: state.enabled,
            loading: state.loading,
            onTap: () => calls++,
          ));
      await tester.tap(find.byType(Button));
      expect(calls, 1);
      expect(find.byIcon(Icons.arrow_forward_rounded),
          state.loading ? findsNothing : findsOneWidget);
      expect(find.byType(CircularProgressIndicator),
          state.loading ? findsOneWidget : findsNothing);
      expect(tester.getSize(find.byType(Button)).height, 52);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('a centered button keeps its 52 pixel minimum height',
      (tester) async {
    await _pump(
      tester,
      const Button(
        text: 'Sign in',
        height: 52,
        radius: AppTokens.rLg,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: _enabledStyle,
      ),
    );
    expect(tester.getSize(find.byType(Button)).height, 52);
    expect(tester.getSize(find.byType(Button)).width, 320);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long text wraps and grows at double text scale in 320 pixels',
      (tester) async {
    const label = 'Confirm your new password and return to sign in securely';
    await _pump(
      tester,
      const Button(
        text: label,
        height: 52,
        radius: AppTokens.rLg,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: _enabledStyle,
      ),
      textScale: 2,
    );
    expect(tester.getSize(find.byType(Button)).height, greaterThan(52));
    expect(tester.getSize(find.text(label)).width, lessThanOrEqualTo(288));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'loading prevents repeat taps and disabled style and semantics apply',
      (tester) async {
    final loading = ValueNotifier(false);
    addTearDown(loading.dispose);
    final semantics = tester.ensureSemantics();
    var calls = 0;
    try {
      await _pump(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: loading,
          builder: (_, value, __) => Button(
            text: 'Sign in',
            loading: value,
            height: 52,
            radius: AppTokens.rLg,
            textStyle: _enabledStyle,
            disabledTextStyle: _disabledStyle,
            onTap: () {
              calls++;
              loading.value = true;
            },
          ),
        ),
      );
      await tester.tap(find.byType(Button));
      await tester.pump();
      await tester.tap(find.byType(Button));
      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<Text>(find.text('Sign in')).style, _disabledStyle);
      final loadingData =
          tester.getSemantics(_buttonSemantics).getSemanticsData();
      expect(loadingData.flagsCollection.isButton, isTrue);
      expect(loadingData.flagsCollection.isEnabled, Tristate.isFalse);
      expect(loadingData.flagsCollection.isLiveRegion, isTrue);
      expect(loadingData.hasAction(SemanticsAction.tap), isFalse);

      await _pump(
        tester,
        Button(
          text: 'Sign in',
          enabled: false,
          height: 52,
          radius: AppTokens.rLg,
          textStyle: _enabledStyle,
          disabledTextStyle: _disabledStyle,
          onTap: () => calls++,
        ),
      );
      await tester.tap(find.byType(Button));
      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.widget<Text>(find.text('Sign in')).style, _disabledStyle);
      final disabledData =
          tester.getSemantics(_buttonSemantics).getSemanticsData();
      expect(disabledData.flagsCollection.isEnabled, Tristate.isFalse);
      expect(disabledData.flagsCollection.isLiveRegion, isFalse);
      expect(disabledData.hasAction(SemanticsAction.tap), isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
