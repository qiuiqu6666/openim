import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/exchange/widgets/wallet_exchange_form.dart';

void main() {
  testWidgets('exchange offers only returned currencies and handles none',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    Future<void> pump(List<FundCurrency> currencies) =>
        tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: WalletExchangeForm(
          from: FundCurrency.usdt,
          to: FundCurrency.bi99,
          currencies: currencies,
          amountController: controller,
          available: '0',
          locked: false,
          onFrom: (_) {},
          onTo: (_) {},
          onReverse: () {},
          onAmountChanged: () {},
        ))));
    await pump(FundCurrency.values);
    final dropdown = tester.widget<DropdownButton<FundCurrency>>(
        find.byKey(const ValueKey('wallet-swap-from')));
    expect(dropdown.items!.map((item) => item.value),
        [FundCurrency.usdt, FundCurrency.bi99]);
    expect(find.text('TRX'), findsNothing);
    await pump([]);
    expect(find.text('暂无可用币种'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
