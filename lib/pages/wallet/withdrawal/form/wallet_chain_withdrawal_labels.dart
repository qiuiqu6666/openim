import '../../data/wallet_fund_api.dart';
import '../../host/wallet_i18n.dart';
import '../../widgets/currency_rules/wallet_currency_rule_labels.dart';
import '../../widgets/currency_rules/wallet_withdrawal_policy_labels.dart';

/// Copy for the chain withdrawal form; values always come from wallet state.
class WalletChainWithdrawalLabels {
  const WalletChainWithdrawalLabels(this.i18n);

  final AppI18n i18n;

  WalletWithdrawalPolicyLabels get _policy =>
      WalletWithdrawalPolicyLabels(i18n);

  String title(FundCurrency currency) => i18n.format(
        zhHans: '提现 {currency}',
        zhHant: '提現 {currency}',
        en: 'Withdraw {currency}',
        ja: '{currency}を出金',
        ko: '{currency} 출금',
        vars: {'currency': currency.displayName},
      );

  String get address => i18n.t(
        zhHans: '收款地址',
        zhHant: '收款地址',
        en: 'Recipient address',
        ja: '受取アドレス',
        ko: '받는 주소',
      );

  String get addressHint => i18n.t(
        zhHans: '长按粘贴收款地址',
        zhHant: '長按貼上收款地址',
        en: 'Long press to paste the recipient address',
        ja: '長押しして受取アドレスを貼り付け',
        ko: '길게 눌러 받는 주소 붙여넣기',
      );

  String get networkLabel => i18n.t(
        zhHans: '转账网络',
        zhHant: '轉帳網路',
        en: 'Transfer network',
        ja: '送金ネットワーク',
        ko: '전송 네트워크',
      );

  String get quantity => i18n.t(
        zhHans: '提现数量',
        zhHant: '提現數量',
        en: 'Amount',
        ja: '数量',
        ko: '수량',
      );

  String minimumHint(String? minimum) => i18n.format(
        zhHans: '最少 {minimum}',
        zhHant: '最少 {minimum}',
        en: 'Minimum {minimum}',
        ja: '最小 {minimum}',
        ko: '최소 {minimum}',
        vars: {'minimum': _known(minimum)},
      );

  String balance(String? balance, FundCurrency currency) => i18n.format(
        zhHans: '可用 {value}',
        zhHant: '可用 {value}',
        en: 'Available {value}',
        ja: '利用可能 {value}',
        ko: '사용 가능 {value}',
        vars: {'value': amount(balance, currency)},
      );

  String get all => i18n.t(
        zhHans: '全部',
        zhHant: '全部',
        en: 'All',
        ja: '全額',
        ko: '전체',
      );

  String get info => i18n.t(
        zhHans: '查看说明',
        zhHant: '查看說明',
        en: 'View information',
        ja: '説明を見る',
        ko: '설명 보기',
      );

  String get selectNetwork => i18n.t(
        zhHans: '选择网络',
        zhHant: '選擇網路',
        en: 'Select a transfer network',
        ja: '送金ネットワークを選択',
        ko: '전송 네트워크 선택',
      );

  String get networkChoice => i18n.t(
        zhHans: '选择转账网络',
        zhHant: '選擇轉帳網路',
        en: 'Choose transfer network',
        ja: '送金ネットワークを選択',
        ko: '전송 네트워크 선택',
      );

  String get receivedLabel => i18n.t(
        zhHans: '到账数量',
        zhHant: '到帳數量',
        en: 'Amount received',
        ja: '受取数量',
        ko: '받는 수량',
      );

  String get feeLabel => i18n.t(
        zhHans: '网络手续费',
        zhHant: '網路手續費',
        en: 'Network fee',
        ja: 'ネットワーク手数料',
        ko: '네트워크 수수료',
      );

  String totalDebit(String? total, FundCurrency currency) => i18n.format(
        zhHans: '总扣款：{value}',
        zhHant: '總扣款：{value}',
        en: 'Total debit: {value}',
        ja: '合計引落額：{value}',
        ko: '총 차감액: {value}',
        vars: {'value': amount(total, currency)},
      );

  String amount(String? value, FundCurrency currency) =>
      WalletCurrencyRuleLabels(i18n).amount(_known(value), currency);

  String get feeNote => i18n.t(
        zhHans: '手续费另行扣除，总扣款为提现数量与手续费之和。',
        zhHant: '手續費另行扣除，總扣款為提現數量與手續費之和。',
        en: 'The fee is charged separately. Total debit is the withdrawal amount plus the fee.',
        ja: '手数料は別途差し引かれます。合計引落額は出金数量と手数料の合計です。',
        ko: '수수료는 별도로 차감됩니다. 총 차감액은 출금 수량과 수수료의 합계입니다.',
      );

  String get addressNote => i18n.t(
        zhHans: '请输入有效的 TRON 钱包地址，并确认收款平台与转账网络一致。',
        zhHant: '請輸入有效的 TRON 錢包地址，並確認收款平台與轉帳網路一致。',
        en: 'Enter a valid TRON wallet address and confirm that the receiving platform uses the same transfer network.',
        ja: '有効な TRON ウォレットアドレスを入力し、受取先のプラットフォームと送金ネットワークが一致することを確認してください。',
        ko: '유효한 TRON 지갑 주소를 입력하고 받는 플랫폼과 전송 네트워크가 일치하는지 확인해 주세요.',
      );

  String get networkNote => i18n.t(
        zhHans: '目前支持 TRON 网络，请确认收款平台也使用 TRON 网络。',
        zhHant: '目前支援 TRON 網路，請確認收款平台也使用 TRON 網路。',
        en: 'TRON is currently supported. Confirm that the receiving platform also uses TRON.',
        ja: '現在 TRON ネットワークに対応しています。受取先も TRON を使用していることを確認してください。',
        ko: '현재 TRON 네트워크를 지원합니다. 받는 플랫폼도 TRON을 사용하는지 확인해 주세요.',
      );

  String get amountNote => i18n.t(
        zhHans: '提现数量为到账本金，手续费另行扣除。全额为可用余额减去手续费。',
        zhHant: '提現數量為到帳本金，手續費另行扣除。全額為可用餘額減去手續費。',
        en: 'The withdrawal amount is the principal received; the fee is charged separately. All uses the available balance minus the fee.',
        ja: '出金数量は受取元本で、手数料は別途差し引かれます。全額は利用可能残高から手数料を差し引いた額です。',
        ko: '출금 수량은 받는 원금이며 수수료는 별도로 차감됩니다. 전체 수량은 사용 가능한 잔액에서 수수료를 뺀 금액입니다.',
      );

  String get securityNote => i18n.t(
        zhHans: '请勿直接提现至众筹或 ICO 地址，可能导致资产无法找回。',
        zhHant: '請勿直接提現至眾籌或 ICO 地址，可能導致資產無法找回。',
        en: 'Do not withdraw directly to crowdfunding or ICO addresses; your assets may be unrecoverable.',
        ja: 'クラウドファンディングや ICO のアドレスに直接出金しないでください。資産を回収できなくなる可能性があります。',
        ko: '크라우드펀딩 또는 ICO 주소로 직접 출금하지 마세요. 자산을 되찾지 못할 수 있습니다.',
      );

  String get addressInvalid => i18n.t(
        zhHans: '请输入有效的 TRON 收款地址',
        zhHant: '請輸入有效的 TRON 收款地址',
        en: 'Enter a valid TRON recipient address.',
        ja: '有効な TRON の受取アドレスを入力してください。',
        ko: '유효한 TRON 받는 주소를 입력해 주세요.',
      );

  String get selfAddress => i18n.t(
        zhHans: '提现地址不能和转出地址相同',
        zhHant: '提現地址不能和轉出地址相同',
        en: 'The withdrawal address cannot be the same as the sending address.',
        ja: '出金先アドレスは送金元アドレスと同じにできません。',
        ko: '출금 주소는 보내는 주소와 같을 수 없습니다.',
      );

  String get invalidAmount => i18n.t(
        zhHans: '请输入有效的提现数量',
        zhHant: '請輸入有效的提現數量',
        en: 'Enter a valid withdrawal amount.',
        ja: '有効な出金数量を入力してください。',
        ko: '유효한 출금 수량을 입력해 주세요.',
      );

  String get unsupported => i18n.t(
        zhHans: '该币种暂不支持链上提现',
        zhHant: '該幣種暫不支援鏈上提現',
        en: 'On-chain withdrawals are unavailable for this currency.',
        ja: 'この通貨のオンチェーン出金には対応していません。',
        ko: '이 통화는 온체인 출금을 지원하지 않습니다.',
      );

  String get withdraw => i18n.t(
        zhHans: '提现',
        zhHant: '提現',
        en: 'Withdraw',
        ja: '出金',
        ko: '출금',
      );

  String get help => i18n.t(
        zhHans: '帮助',
        zhHant: '幫助',
        en: 'Help',
        ja: 'ヘルプ',
        ko: '도움말',
      );

  String get records => i18n.t(
        zhHans: '提现记录',
        zhHant: '提現記錄',
        en: 'Withdrawal history',
        ja: '出金履歴',
        ko: '출금 내역',
      );

  String get paste => i18n.t(
        zhHans: '粘贴地址',
        zhHant: '貼上地址',
        en: 'Paste address',
        ja: 'アドレスを貼り付け',
        ko: '주소 붙여넣기',
      );

  String get scan => i18n.t(
        zhHans: '扫码填写地址',
        zhHant: '掃碼填寫地址',
        en: 'Scan address',
        ja: 'アドレスをスキャン',
        ko: '주소 스캔',
      );

  String get acknowledge => i18n.t(
        zhHans: '我知道了',
        zhHant: '我知道了',
        en: 'Got it',
        ja: '確認しました',
        ko: '확인했어요',
      );

  String get loading => _policy.loading;
  String get unavailable => _policy.unavailable;
  String get accountChanged => _policy.accountChanged;
  String get retry => _policy.retry;

  static String _known(String? value) =>
      value == null || value.trim().isEmpty ? '--' : value;
}
