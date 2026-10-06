import '../data/wallet_fund_api.dart';
import '../host/wallet_i18n.dart';

/// Copy belonging to the chain withdrawal review, rather than payment auth.
class WalletWithdrawalReviewLabels {
  const WalletWithdrawalReviewLabels(this.i18n);

  final AppI18n i18n;

  String get title => i18n.t(
      zhHans: '提现确认',
      zhHant: '提現確認',
      en: 'Review withdrawal',
      ja: '出金確認',
      ko: '출금 확인');
  String get chainTitle => i18n.t(
      zhHans: '链上提现',
      zhHant: '鏈上提現',
      en: 'On-chain withdrawal',
      ja: 'オンチェーン出金',
      ko: '온체인 출금');
  String get receiver => i18n.t(
      zhHans: '收款地址',
      zhHant: '收款地址',
      en: 'Recipient address',
      ja: '受取アドレス',
      ko: '받는 주소');
  String get copyAddress => i18n.t(
      zhHans: '复制地址',
      zhHant: '複製地址',
      en: 'Copy address',
      ja: 'アドレスをコピー',
      ko: '주소 복사');
  String get submit => i18n.t(
      zhHans: '确认提现',
      zhHant: '確認提現',
      en: 'Confirm withdrawal',
      ja: '出金を確定',
      ko: '출금 확인');
  String get submitting => i18n.t(
      zhHans: '提交中', zhHant: '提交中', en: 'Submitting', ja: '送信中', ko: '제출 중');
  String get feeExplanation => i18n.t(
      zhHans: '手续费使用提现币种，提现金额和手续费从可用余额一并扣除。',
      zhHant: '手續費使用提現幣種，提現金額和手續費從可用餘額一併扣除。',
      en: 'The fee is charged in the withdrawal currency. The withdrawal amount and fee are deducted from your available balance.',
      ja: '手数料は出金通貨で請求され、出金額とともに利用可能残高から差し引かれます。',
      ko: '수수료는 출금 통화로 부과되며 출금 금액과 함께 사용 가능한 잔액에서 차감됩니다.');
  String get broadcastExplanation => i18n.t(
      zhHans: '提交后以订单结果为准；已提交链上表示广播成功。',
      zhHant: '提交後以訂單結果為準；已提交鏈上表示廣播成功。',
      en: 'After submission, the order result is authoritative. Submitted on-chain means the transaction was broadcast.',
      ja: '送信後は注文結果をご確認ください。オンチェーン送信済みはトランザクションの配信成功を示します。',
      ko: '제출 후 주문 결과를 확인하세요. 온체인 제출은 트랜잭션 전송에 성공했음을 뜻합니다.');
  String available(FundAmount amount) {
    final value = '${amount.displayDecimal} ${amount.currency.displayName}';
    return i18n.t(
        zhHans: '可用 $value',
        zhHant: '可用 $value',
        en: 'Available $value',
        ja: '利用可能 $value',
        ko: '사용 가능 $value');
  }
}
