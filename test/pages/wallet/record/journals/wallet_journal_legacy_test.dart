import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/wallet/host/wallet_i18n.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_entry.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_filter_options.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_presentation.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_record_mapper.dart';
import 'package:openim/pages/wallet/record/wallet_record_models.dart';

void main() {
  setUp(() {
    final old = Get.locale;
    Get.locale = const Locale('zh', 'CN');
    addTearDown(() => Get.locale = old);
  });

  for (final item in const [
    ('withdraw_fee_refund', '提现手续费退回', 'income', '1'),
    ('life_payment', '生活缴费', 'expense', '-1'),
    ('life_payment_refund', '生活缴费退回', 'income', '1'),
    ('group_create', '建群费用', 'expense', '-1'),
  ]) {
    test('${item.$1} keeps posted meaning without inventing linked order', () {
      final entry = WalletJournalEntry.fromJson({
        'id': 'legacy-journal',
        'currency': 'USDT',
        'bizType': item.$1,
        'type': item.$1,
        'title': item.$2,
        'direction': item.$3,
        'amount': '1',
        'availableDelta': item.$4,
        'frozenDelta': '0',
        'assetDelta': item.$4,
        'beforeAvailable': '10',
        'afterAvailable': item.$3 == 'income' ? '11' : '9',
        'balanceSource': 'legacy_snapshot',
        'createdAt': 1791244800000,
        'bizID': 'legacy-chat99-ledger:legacy-1:entry',
        'orderID': '',
        'counterpartyID': '',
        'groupID': '',
        'remark': '',
        'reason': '',
        'orderStatus': '',
        'chainTxID': '',
      });
      expect(walletJournalTitle(entry, AppI18n.current), item.$2);
      expect(walletJournalFilterLabel(item.$1, AppI18n.current), item.$2);
      expect(walletJournalBizTypes[item.$1], contains(item.$1));
      final record = entry.toWalletRecord();
      expect(record.orderNo, isEmpty);
      expect(record.hash, isEmpty);
      expect(record.income, item.$3 == 'income');
      if (item.$1 == 'withdraw_fee_refund') {
        expect(record.isChainWithdraw, isFalse);
      }
    });
  }
}
