import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/fund_send_page.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_fund_repository.dart';
import 'package:openim/pages/wallet/wallet_controller.dart';
import 'package:openim/pages/wallet/withdrawal/form/wallet_chain_withdrawal_screen.dart';
import 'package:openim/pages/wallet/withdraw_coin_picker_screen.dart';
import 'package:openim/pages/wallet/withdraw_transfer_target_validator.dart';

import '../data/wallet_fund_test_api.dart';
import '../home/wallet_home_test_support.dart';

void main() {
  for (final kind in WithdrawTransferTargetKind.values) {
    testWidgets('API currencies preserve $kind selection and exact units',
        (tester) async {
      final api = WalletTestFundApi();
      final repository =
          WalletFundRepository(api: api, accountProvider: () => 'server:user');
      final controller = WalletController(repo: HomeTestRepository());
      addTearDown(controller.dispose);
      final observer = HomeRouteObserver();
      await pumpWalletHome(tester,
          controller: controller,
          observer: observer,
          page: WithdrawCoinPickerScreen(
              initialTargetKind: kind, repository: repository));
      await tester.pumpAndSettle();
      expect(find.text('USDT'), findsWidgets);
      expect(find.text('TRX'), findsWidgets);
      expect(
          find.text('99'),
          kind == WithdrawTransferTargetKind.chain
              ? findsNothing
              : findsWidgets);
      // Inspect the actual next route without mounting SDK-backed contacts.
      await tester.tap(find.text('USDT').first);
      final pushed = observer.lastPush! as PageRouteBuilder;
      final page = pushed.pageBuilder(
          tester.element(find.byType(WithdrawCoinPickerScreen)),
          const AlwaysStoppedAnimation(1),
          const AlwaysStoppedAnimation(0));
      if (kind == WithdrawTransferTargetKind.chain) {
        expect(page, isA<WalletChainWithdrawalScreen>());
        final chain = page as WalletChainWithdrawalScreen;
        expect(chain.initialAddress, isEmpty);
        expect(chain.payMethod.balMinor, 12345678);
        expect(chain.payMethod.scale, 6);
        expect(chain.coin.availableRaw, '12.345678');
        expect(chain.coin.frozen, '4.1');
      } else {
        expect(page, isA<FundSendPage>());
        final friend = page as FundSendPage;
        expect(friend.isRedPacket, isFalse);
        expect(friend.internalWithdrawal, isTrue);
        expect(friend.initialCurrency, FundCurrency.usdt);
      }
      observer.navigator!.removeRoute(pushed);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
