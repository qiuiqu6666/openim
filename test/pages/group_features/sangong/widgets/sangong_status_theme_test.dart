import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_bet_submit_cutoff.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_bet_preview_sheet.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_round_settle_dialog.dart';

import '../sangong_test_support.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  testWidgets('preview statuses remain readable as light changes to dark',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = sangongTestRuntime(sangongTestContext(SangongTestApi()));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    const sheet = SangongBetPreviewSheet(
        preview: SangongBetPreview(
            excludedAfterCutoff: 2,
            report: SangongBetPreviewReport(entries: [
              SangongBetPreviewEntry(
                  nickname: '下注用户',
                  text: '1门100',
                  amount: 100,
                  status: 'placed')
            ])),
        cutoff: SangongBetSubmitCutoff(excludeMsgSeqs: [4]),
        roundId: 1,
        doorCount: 2);
    await pumpSangongPage(tester, runtime, const Scaffold(body: sheet));
    final state = tester.state(find.byType(SangongBetPreviewSheet));
    for (final dark in [false, true, false]) {
      await pumpSangongPage(tester, runtime, const Scaffold(body: sheet),
          dark: dark);
      await tester.pumpAndSettle();
      expect(
          identical(tester.state(find.byType(SangongBetPreviewSheet)), state),
          isTrue);
      final success = tester.widget<Text>(find.text('已落注')).style!.color!;
      expect(success, dark ? AppTokens.successDark : const Color(0xFF2E7D32));
      final errors = tester.widgetList<Text>(find.byWidgetPredicate((widget) =>
          widget is Text &&
          (widget.data?.startsWith('排除消息') == true ||
              widget.data?.contains('截止点之后') == true)));
      expect(errors.length, 2);
      for (final error in errors) {
        expect(error.style!.color, AppTokens.paymentError(dark: dark));
        if (dark) {
          expect(_contrast(error.style!.color!, AppTokens.surfaceDark),
              greaterThanOrEqualTo(4.5));
        }
      }
      if (dark) {
        expect(_contrast(success, AppTokens.surfaceDark),
            greaterThanOrEqualTo(4.5));
      }
      expect(tester.takeException(), isNull);
    }
  });

  for (final valid in [false, true]) {
    testWidgets('draw check status updates with theme, valid=$valid',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final runtime = sangongTestRuntime(sangongTestContext(SangongTestApi()));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      final sheet = SangongRoundSettleDialog(
          drawStatus: SangongDrawStatus(doorCount: 2, draws: [
        const SangongDoorDraw(door: 1, amount: '11'),
        SangongDoorDraw(door: 2, amount: valid ? '19' : '12')
      ]));
      await pumpSangongPage(tester, runtime, Scaffold(body: sheet));
      final state = tester.state(find.byType(SangongRoundSettleDialog));
      for (final dark in [false, true, false]) {
        await pumpSangongPage(tester, runtime, Scaffold(body: sheet),
            dark: dark);
        await tester.pumpAndSettle();
        final status = tester
            .widget<Text>(find.text(valid ? '尾数校验通过' : '尾数合计 3，须为 0/10/20…'));
        expect(
            status.style!.color,
            valid
                ? AppTokens.statusSuccess(dark: dark)
                : AppTokens.paymentError(dark: dark));
        expect(
            identical(
                tester.state(find.byType(SangongRoundSettleDialog)), state),
            isTrue);
        final entries = tester.widgetList<TextField>(find.byType(TextField));
        expect(entries.map((entry) => entry.controller!.text),
            orderedEquals([valid ? '19' : '12', '11']));
        if (dark) {
          expect(_contrast(status.style!.color!, AppTokens.surfaceDark),
              greaterThanOrEqualTo(4.5));
        }
        expect(tester.takeException(), isNull);
      }
    });
  }
}
