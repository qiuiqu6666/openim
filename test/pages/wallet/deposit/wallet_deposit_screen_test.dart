import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_page.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_query.dart';
import 'package:openim/pages/wallet/record/wallet_record_screen.dart';

import 'support/wallet_deposit_qr_expectation.dart';
import 'support/wallet_deposit_test_support.dart';

void main() {
  testWidgets(
      'pending has no usable address; ready QR uses the endpoint, not the legacy caller',
      (tester) async {
    final api = WalletTestFundApi(address: depositAddressFixture(ready: false));
    await pumpWalletDeposit(tester, api: api);
    expect(find.text('充值地址生成中'), findsOneWidget);
    expect(depositKey('wallet-deposit-copy'), findsNothing);
    expect(depositKey('wallet-deposit-address-copy'), findsNothing);
    expect(depositKey('wallet-deposit-qr'), findsNothing);
    api.address = depositAddressFixture();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(api.addressCalls, 2);
    await expectDepositAddressQr(
        tester, depositKey('wallet-deposit-qr'), testDepositAddress);
    expect(tester.widget<Text>(depositKey('wallet-deposit-address')).data,
        testDepositAddress);
    expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.textContaining('USDT')),
        findsOneWidget);
    expect(
        tester.widget<Text>(depositKey('wallet-deposit-network')).data, 'Tron');
    expect(find.text('legacy-address-must-not-be-used'), findsNothing);
    expect(find.textContaining('19 个区块'), findsOneWidget);
    expect(find.text('暂未提供'), findsNothing);
    expect(find.text('0.1 USDT'), findsOneWidget);
    expect(find.text('约2分钟'), findsOneWidget);
    expect(find.text('33 次区块确认'), findsOneWidget);
    expect(api.balanceCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'USDT and TRX share the real address without contract information',
      (tester) async {
    final api = WalletTestFundApi();
    final service = DepositTestShareService();
    await pumpWalletDeposit(tester, api: api, share: service);
    expect(depositKey('wallet-deposit-contract-preview'), findsNothing);
    expect(depositKey('wallet-deposit-contract-info'), findsNothing);
    expect(find.text('合约信息'), findsNothing);
    expect(find.text(testUsdtContract), findsNothing);
    await tester.tap(depositKey('wallet-deposit-currency'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TRX').last);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.textContaining('TRX')),
        findsOneWidget);
    expect(depositKey('wallet-deposit-contract-preview'), findsNothing);
    expect(depositKey('wallet-deposit-contract-info'), findsNothing);
    expect(find.text('合约信息'), findsNothing);
    await expectDepositAddressQr(
        tester, depositKey('wallet-deposit-qr'), testDepositAddress);
    await tester.ensureVisible(depositKey('wallet-deposit-address-copy'));
    await tester.tap(depositKey('wallet-deposit-address-copy'));
    await tester.pumpAndSettle();
    expect(service.copies, [testDepositAddress]);
    await tester.ensureVisible(depositKey('wallet-deposit-share'));
    await tester.tap(depositKey('wallet-deposit-share'));
    await tester.pumpAndSettle();
    expect(depositKey('wallet-deposit-share-sheet'), findsOneWidget);
    await tester.ensureVisible(depositKey('wallet-deposit-system-share'));
    await tester.tap(depositKey('wallet-deposit-system-share'));
    await tester.pumpAndSettle();
    expect(service.imageShares, hasLength(1));
    expect(service.shares, isEmpty);
    expect(api.addressCalls, 1);
    await EasyLoading.dismiss(animation: false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('covered and background deposit routes stop allocation retries',
      (tester) async {
    final api =
        _DepositNavigationApi(address: depositAddressFixture(ready: false));
    await pumpWalletDeposit(tester, api: api);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(seconds: 12));
    expect(api.addressCalls, 1);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(api.addressCalls, 2);
    await tester.tap(depositKey('wallet-deposit-records'));
    await tester.pumpAndSettle();
    expect(find.byType(WalletRecordScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 12));
    expect(api.addressCalls, 2);
    expect(api.journalCalls, 1);
    expect(api.depositCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('platform chain deposit remains explicitly unsupported',
      (tester) async {
    final api = WalletTestFundApi();
    await pumpWalletDeposit(tester, api: api, currency: FundCurrency.bi99);
    expect(find.text('99币不支持链上充值'), findsOneWidget);
    expect(depositKey('wallet-deposit-qr'), findsNothing);
    expect(api.addressCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'ready address remains usable on 320px large text ${brightness.name}',
        (tester) async {
      final api = WalletTestFundApi();
      await pumpWalletDeposit(tester,
          api: api,
          brightness: brightness,
          size: const Size(320, 844),
          textScale: 2);
      expect(tester.takeException(), isNull);
      final qr = tester.getRect(depositKey('wallet-deposit-qr'));
      expect(qr.left, greaterThanOrEqualTo(0));
      expect(qr.right, lessThanOrEqualTo(320));
      expect(api.addressCalls, 1);
      expect(tester.widget<Text>(depositKey('wallet-deposit-address')).data,
          testDepositAddress);
      final scrollable = find
          .descendant(
              of: depositKey('wallet-deposit-scroll'),
              matching: find.byType(Scrollable))
          .first;
      expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
          greaterThan(0));
      // The button is a later ListView child, beyond the large-text cache.
      // Scrolling builds it; ensureVisible alone requires it to exist already.
      await tester.scrollUntilVisible(depositKey('wallet-deposit-share'), 260,
          scrollable: scrollable, maxScrolls: 30);
      await tester.pumpAndSettle();
      expect(depositKey('wallet-deposit-share').hitTestable(), findsOneWidget,
          reason:
              'share=${tester.getRect(depositKey("wallet-deposit-share"))}; '
              'viewport=${tester.getRect(depositKey("wallet-deposit-scroll"))}; '
              'offset=${tester.state<ScrollableState>(scrollable).position.pixels}');
      expect(tester.getSize(depositKey('wallet-deposit-share')).height,
          greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _DepositNavigationApi extends WalletTestFundApi {
  _DepositNavigationApi({required super.address});

  int journalCalls = 0;

  @override
  Future<WalletJournalPage> fetchJournals(WalletJournalQuery query) async {
    journalCalls++;
    return WalletJournalPage(
        items: const [], limit: query.limit, hasMore: false, nextCursor: '');
  }
}
