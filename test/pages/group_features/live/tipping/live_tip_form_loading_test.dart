import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/live/tipping/live_tip_form.dart';
import 'package:openim/pages/group_features/live/models/live_tip_currency.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('full tip form keeps geometry while loading dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final amount = TextEditingController(), memo = TextEditingController();
      final loading = ValueNotifier(true);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        amount.dispose();
        memo.dispose();
        loading.dispose();
      });
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: Scaffold(
            body: Align(
          alignment: Alignment.bottomCenter,
          child: ValueListenableBuilder<bool>(
              valueListenable: loading,
              builder: (_, value, __) => LiveTipForm(
                    currencies: const [
                      LiveTipCurrency('BI99', '元', 2),
                      LiveTipCurrency('USDT', 'USDT', 6)
                    ],
                    currency: const LiveTipCurrency('BI99', '元', 2),
                    amount: amount,
                    memo: memo,
                    loading: value,
                    busy: false,
                    pending: false,
                    pendingUnavailable: false,
                    balance: null,
                    balanceLoading: value,
                    balanceFailed: false,
                    onRefreshBalance: () {},
                    onCurrency: (_) {},
                    onAmountChanged: () {},
                    onClose: () {},
                    onSubmit: null,
                  )),
        )),
      ));
      await tester.pump();
      final amountField = find.byKey(const ValueKey('live-tip-amount'));
      final memoField = find.byKey(const ValueKey('live-tip-memo'));
      expect(amountField, findsOneWidget);
      expect(memoField, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.widget<TextField>(amountField).enabled, isFalse);
      final before = [
        tester.getRect(amountField),
        tester.getRect(memoField),
        tester.getRect(find.text('确认打赏'))
      ];
      loading.value = false;
      await tester.pump();
      expect(tester.widget<TextField>(amountField).enabled, isTrue);
      expect([
        tester.getRect(amountField),
        tester.getRect(memoField),
        tester.getRect(find.text('确认打赏'))
      ], before);
      expect(tester.takeException(), isNull);
    });
  }
}
