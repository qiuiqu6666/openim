import '../../data/currency_rules/wallet_withdrawal_policy.dart';
import '../../data/wallet_fund_api.dart';
import '../../host/wallet_i18n.dart';
import 'wallet_currency_rule_labels.dart';

class WalletWithdrawalPolicyLabels {
  const WalletWithdrawalPolicyLabels(this.i18n);
  final AppI18n i18n;

  String minimum(WalletCurrencyRule? rule, FundCurrency currency) =>
      i18n.format(
        zhHans: '最低提现：{value}',
        zhHant: '最低提現：{value}',
        en: 'Minimum withdrawal: {value}',
        ja: '最小出金額：{value}',
        ko: '최소 출금액: {value}',
        vars: {
          'value': WalletCurrencyRuleLabels(i18n)
              .amount(rule?.minWithdrawAmount, currency)
        },
      );

  String fee(WalletCurrencyRule? rule, FundCurrency currency) => feeAmount(
      rule?.withdrawFeeCurrency == currency ? rule?.withdrawFee : null,
      currency);

  String feeAmount(String? fee, FundCurrency currency) => i18n.format(
        zhHans: '手续费：{value}',
        zhHant: '手續費：{value}',
        en: 'Fee: {value}',
        ja: '手数料：{value}',
        ko: '수수료: {value}',
        vars: {'value': WalletCurrencyRuleLabels(i18n).amount(fee, currency)},
      );

  String total(FundAmount amount) => totalAmount(amount, amount.currency);

  String totalAmount(FundAmount? amount, FundCurrency currency) => i18n.format(
        zhHans: '总扣款：{value}',
        zhHant: '總扣款：{value}',
        en: 'Total debit: {value}',
        ja: '合計引落額：{value}',
        ko: '총 차감액: {value}',
        vars: {
          'value':
              WalletCurrencyRuleLabels(i18n).amount(amount?.decimal, currency)
        },
      );

  String issue(WalletWithdrawalPolicyIssue issue, WalletCurrencyRule? rule) {
    if (issue == WalletWithdrawalPolicyIssue.incomplete) return unavailable;
    if (issue == WalletWithdrawalPolicyIssue.insufficientBalance) {
      return i18n.t(
        zhHans: '可用余额不足以支付提现金额和手续费',
        zhHant: '可用餘額不足以支付提現金額和手續費',
        en: 'Available balance cannot cover the withdrawal and fee.',
        ja: '出金額と手数料を支払う残高が不足しています。',
        ko: '출금액과 수수료를 지불할 가용 잔액이 부족합니다.',
      );
    }
    return i18n.format(
      zhHans: '提现金额不能低于 {minimum}',
      zhHant: '提現金額不能低於 {minimum}',
      en: 'Withdrawal amount must be at least {minimum}.',
      ja: '出金額は{minimum}以上にしてください。',
      ko: '출금액은 최소 {minimum} 이상이어야 합니다.',
      vars: {
        'minimum': rule == null
            ? WalletCurrencyRuleLabels(i18n).notProvided
            : WalletCurrencyRuleLabels(i18n)
                .amount(rule.minWithdrawAmount, rule.currency)
      },
    );
  }

  String get loading => i18n.t(
        zhHans: '正在读取提现规则',
        zhHant: '正在讀取提現規則',
        en: 'Loading withdrawal rules',
        ja: '出金ルールを読み込み中',
        ko: '출금 규칙을 불러오는 중',
      );

  String get unavailable => i18n.t(
        zhHans: '提现规则暂不可用，请重试',
        zhHant: '提現規則暫不可用，請重試',
        en: 'Withdrawal rules are unavailable. Please retry.',
        ja: '出金ルールを取得できません。再試行してください。',
        ko: '출금 규칙을 사용할 수 없습니다. 다시 시도해 주세요.',
      );

  String get accountChanged => i18n.t(
        zhHans: '账号已变化，请重新打开钱包',
        zhHant: '帳號已變更，請重新開啟錢包',
        en: 'Account changed. Reopen the wallet.',
        ja: 'アカウントが変更されました。ウォレットを開き直してください。',
        ko: '계정이 변경되었습니다. 지갑을 다시 열어 주세요.',
      );

  String get retry => i18n.t(
        zhHans: '重新读取规则',
        zhHant: '重新讀取規則',
        en: 'Reload rules',
        ja: 'ルールを再取得',
        ko: '규칙 다시 불러오기',
      );
}
