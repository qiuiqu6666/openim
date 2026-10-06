import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/wallet/host/wallet_i18n.dart';
import 'package:openim/pages/wallet/widgets/currency_rules/wallet_currency_rule_labels.dart';
import 'package:openim/services/fund_models.dart';

void main() {
  final locales = <Locale, List<String>>{
    const Locale('zh', 'CN'): [
      '暂未提供',
      '钱包账户',
      '现货账户',
      '资金账户',
      '约59秒',
      '约2分钟',
      '64 次区块确认',
      '无需备注'
    ],
    const Locale('zh', 'TW'): [
      '暫未提供',
      '錢包帳戶',
      '現貨帳戶',
      '資金帳戶',
      '約59秒',
      '約2分鐘',
      '64 次區塊確認',
      '無需備註'
    ],
    const Locale('en'): [
      'Not provided yet',
      'Wallet account',
      'Spot account',
      'Funding account',
      'About 59 sec',
      'About 2 min',
      '64 block confirmations',
      'No memo is required.',
    ],
    const Locale('ja'): [
      '未提供',
      'ウォレット口座',
      '現物口座',
      '資金口座',
      '約59秒',
      '約2分',
      '64ブロックの承認',
      'メモは不要です。'
    ],
    const Locale('ko'): [
      '아직 제공되지 않음',
      '지갑 계정',
      '현물 계정',
      '펀딩 계정',
      '약 59초',
      '약 2분',
      '64개 블록 확인',
      '메모는 필요하지 않습니다.',
    ],
  };
  for (final entry in locales.entries) {
    test('rule values and unknown states use ${entry.key}', () {
      final previousLocale = Get.locale;
      addTearDown(() => Get.locale = previousLocale);
      Get.locale = entry.key;
      final labels = WalletCurrencyRuleLabels(AppI18n.current);
      expect(labels.notProvided, entry.value[0]);
      expect(labels.receivingAccount('wallet'), entry.value[1]);
      expect(labels.receivingAccount('spot'), entry.value[2]);
      expect(labels.receivingAccount('funding'), entry.value[3]);
      expect(labels.receivingAccount(null), labels.notProvided);
      expect(labels.receivingAccount('future-account'), labels.notProvided);
      expect(labels.arrival(59), entry.value[4]);
      expect(labels.arrival(61), entry.value[5]);
      expect(labels.arrival(120), entry.value[5]);
      expect(labels.arrival(null), labels.notProvided);
      expect(labels.arrival(0), isNot(labels.notProvided));
      expect(labels.amount('0.000001', FundCurrency.usdt), '0.000001 USDT');
      expect(labels.amount('0', FundCurrency.trx), '0 TRX');
      expect(labels.amount(null, FundCurrency.usdt), labels.notProvided);
      expect(labels.unlockConfirmations(null), labels.notProvided);
      expect(labels.unlockConfirmations(64), entry.value[6]);
      expect(labels.memoHint(false), entry.value[7]);
      expect(labels.memoHint(true), isNot(labels.memoHint(false)));
      expect(labels.memoHint(null), isNot(labels.memoHint(false)));
      expect(labels.memoHint(null), isNot(labels.memoHint(true)));
      expect(labels.memoHint(null), contains('Memo/Tag'));
    });
  }
}
