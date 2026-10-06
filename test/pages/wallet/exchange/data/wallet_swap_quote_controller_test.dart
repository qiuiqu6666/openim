import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/exchange/data/wallet_swap_quote_controller.dart';

import '../../operations/support/wallet_operation_test_support.dart';

void main() {
  testWidgets('a quote response is ignored after its account changes',
      (tester) async {
    var active = true;
    final api = WalletOperationTestApi();
    final response = Completer<WalletSwapQuote>();
    api.onQuote = (_) => response.future;
    final controller =
        WalletSwapQuoteController(api: api, isActive: () => active);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final amount = FundAmount.parse('1.25', FundCurrency.usdt);
    controller.update(amount, FundCurrency.bi99);
    final pending = controller.refresh();
    expect(controller.loading, true);
    expect(api.quoteRequests, hasLength(1));
    final beforeSwitch = notifications;
    active = false;
    response.complete(walletSwapTestQuote(amount, FundCurrency.bi99));
    expect(await pending, null);
    await tester.pump();
    expect(controller.quote, null);
    expect(controller.validQuote, null);
    expect(controller.error, null);
    expect(controller.loading, false);
    expect(notifications, beforeSwitch);
    expect(api.writes, isEmpty);
    expect(tester.takeException(), null);
  });

  testWidgets(
      'background cancels debounce and resume expires the absolute quote',
      (tester) async {
    var currentTime = DateTime.utc(2026, 10, 6, 5);
    final api = WalletOperationTestApi()..now = () => currentTime;
    final controller = WalletSwapQuoteController(
        api: api, isActive: () => true, now: () => currentTime);
    addTearDown(controller.dispose);
    final amount = FundAmount.parse('1.25', FundCurrency.usdt);
    controller.update(amount, FundCurrency.bi99);
    controller.setForeground(false);
    await tester.pump(const Duration(seconds: 1));
    expect(api.quoteRequests, isEmpty);
    final nextAmount = FundAmount.parse('2', FundCurrency.usdt);
    controller.update(nextAmount, FundCurrency.bi99);
    await tester.pump(const Duration(seconds: 1));
    expect(await controller.refresh(), null);
    expect(api.quoteRequests, isEmpty);
    controller.setForeground(true);
    await tester.pump(const Duration(seconds: 1));
    expect(api.quoteRequests, isEmpty);

    final quote = await controller.refresh();
    expect(quote, isNotNull);
    expect(controller.validQuote, same(quote));
    expect(api.quoteRequests, hasLength(1));
    controller.setForeground(false);
    currentTime = quote!.expiresAt.add(const Duration(milliseconds: 1));
    await tester.pump(const Duration(seconds: 31));
    controller.setForeground(true);
    await tester.pump();
    expect(controller.quote, same(quote));
    expect(controller.validQuote, null);
    expect(controller.error, contains('报价已过期'));
    expect(api.quoteRequests, hasLength(1));
    expect(api.writes, isEmpty);
    expect(tester.takeException(), null);
  });

  testWidgets('a late quote after dispose neither notifies nor throws',
      (tester) async {
    final api = WalletOperationTestApi();
    final response = Completer<WalletSwapQuote>();
    api.onQuote = (_) => response.future;
    final controller =
        WalletSwapQuoteController(api: api, isActive: () => true);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final amount = FundAmount.parse('1.25', FundCurrency.usdt);
    controller.update(amount, FundCurrency.bi99);
    final pending = controller.refresh();
    final beforeDispose = notifications;
    controller.dispose();
    response.complete(walletSwapTestQuote(amount, FundCurrency.bi99));
    expect(await pending, null);
    await tester.pump(const Duration(seconds: 31));
    expect(notifications, beforeDispose);
    expect(controller.quote, null);
    expect(controller.validQuote, null);
    expect(api.quoteRequests, hasLength(1));
    expect(api.writes, isEmpty);
    expect(tester.takeException(), null);
  });
}
