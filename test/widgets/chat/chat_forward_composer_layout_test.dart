import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'toolbox/support/toolbox_fixture.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    for (final inset in [0.0, 24.0, 34.0]) {
      testWidgets('forward send keeps bottom geometry $brightness inset=$inset',
          (tester) async {
        final controller = TextEditingController();
        final state = ValueNotifier<int>(0);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          state.dispose();
        });
        var sends = 0;
        await mountToolbox(
          tester,
          ValueListenableBuilder<int>(
            valueListenable: state,
            builder: (_, value, __) => ChatInputBox(
              controller: controller,
              enabled: value != 1,
              pendingSend: value != 2,
              pendingSending: value == 1,
              onSend: (_) => sends++,
              onTapVoice: () {},
              toolbox: const SizedBox(),
              voiceRecordBar: const SizedBox(),
            ),
          ),
          brightness: brightness,
          safeBottom: inset,
          bottom: true,
        );
        final bar = find.byKey(const ValueKey('chat-composer-bar'));
        final original = tester.getRect(bar);
        final originalHeight = tester.getSize(find.byType(ChatInputBox)).height;
        // Include a failed delivery/retry before the successful completion.
        for (final phase in [1, 0, 1, 2]) {
          state.value = phase;
          await tester.pump();
          expect(tester.getRect(bar), original);
          expect(
              tester.getSize(find.byType(ChatInputBox)).height, originalHeight);
          if (phase == 1) {
            expect(
                tester
                    .widget<ElevatedButton>(find.byType(ElevatedButton))
                    .onPressed,
                isNull);
          }
          await tester.pumpAndSettle();
          expect(tester.getRect(bar), original);
        }
        expect(sends, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
