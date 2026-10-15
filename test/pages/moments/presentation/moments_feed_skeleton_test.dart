import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/presentation/loading/moments_feed_skeleton.dart';

void main() {
  for (final dark in [false, true]) {
    for (final reducedMotion in [false, true]) {
      testWidgets('feed skeleton dark=$dark reducedMotion=$reducedMotion',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: const Scaffold(body: SingleChildScrollView(
              child: SizedBox(width: 320, child: MomentsFeedSkeleton()),
            )),
          ),
        ));
        expect(find.bySemanticsLabel('Loading Moments'), findsOneWidget);
        expect(find.byType(ShaderMask), reducedMotion ? findsNothing : findsOneWidget);
        await tester.pump(const Duration(milliseconds: 400));
        if (reducedMotion) {
          expect(tester.binding.hasScheduledFrame, isFalse);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
