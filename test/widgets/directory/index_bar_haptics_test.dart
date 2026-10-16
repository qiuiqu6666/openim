import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final enabled in [true, false]) {
      testWidgets('$platform index feedback enabled=$enabled', (tester) async {
        final feedback = <Object?>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              feedback.add(call.arguments);
            }
            return null;
          },
        );
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: Center(
              child: BaseIndexBar(
                data: const ['A', 'B', 'C', 'D'],
                itemHeight: 40,
                hapticFeedback: enabled,
              ),
            ),
          ),
        ));
        final start = tester.getCenter(find.text('A'));
        final gesture = await tester.startGesture(start);
        await tester.pump();
        expect(feedback.length, enabled ? 1 : 0);
        // Accept the drag while staying within A.
        await gesture.moveTo(start + const Offset(0, -19));
        await gesture.moveTo(start + const Offset(0, -10));
        await tester.pump();
        expect(feedback.length, enabled ? 1 : 0);
        await gesture.moveTo(tester.getCenter(find.text('B')));
        await tester.pump();
        expect(feedback.length, enabled ? 2 : 0);
        await gesture.moveBy(const Offset(0, 2));
        await tester.pump();
        expect(feedback.length, enabled ? 2 : 0);
        await gesture.moveTo(start);
        await tester.pump();
        expect(feedback.length, enabled ? 3 : 0);
        await gesture.up();
        await tester.pump();
        expect(feedback.length, enabled ? 3 : 0);
        final next = await tester.startGesture(start);
        await tester.pump();
        expect(feedback.length, enabled ? 4 : 0);
        await next.cancel();
        await tester.pump();
        expect(feedback.length, enabled ? 4 : 0);
        expect(feedback, everyElement('HapticFeedbackType.lightImpact'));
      });
    }
  }
}
