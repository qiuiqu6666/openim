import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets('keeps system text scaling and reacts to iOS Reduce Motion',
      (tester) async {
    final dispatcher = tester.binding.platformDispatcher;
    addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
    late MediaQueryData observed;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: AppAccessibilityScope(child: Builder(builder: (context) {
              observed = MediaQuery.of(context);
              return const Text('System text');
            })))));
    expect(observed.textScaler.scale(16), 32);
    expect(observed.disableAnimations, isFalse);
    dispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    expect(observed.disableAnimations, isTrue);
    expect(observed.textScaler.scale(16), 32);
    dispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pump();
    expect(observed.disableAnimations, isFalse);
  });

  test('secondary text maintains small-text contrast on common light surfaces',
      () {
    final fg = AppTokens.textSecondaryLight.computeLuminance();
    for (final color in [
      AppTokens.surfaceLight,
      AppTokens.backgroundLight,
      AppTokens.surfaceAltLight
    ]) {
      expect((color.computeLuminance() + .05) / (fg + .05),
          greaterThanOrEqualTo(4.5));
    }
  });
}
