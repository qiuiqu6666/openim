import '../../../../services/fund_models.dart';
import '../../host/wallet_i18n.dart';

/// Presentation for server-provided currency rules in wallet surfaces.
class WalletCurrencyRuleLabels {
  const WalletCurrencyRuleLabels(this.i18n);

  final AppI18n i18n;

  String get notProvided => i18n.t(
        zhHans: '暂未提供',
        zhHant: '暫未提供',
        en: 'Not provided yet',
        ja: '未提供',
        ko: '아직 제공되지 않음',
      );

  String amount(String? value, FundCurrency currency) =>
      value == null ? notProvided : '$value ${currency.displayName}';

  String receivingAccount(String? type) => switch (type) {
        'wallet' => i18n.t(
            zhHans: '钱包账户',
            zhHant: '錢包帳戶',
            en: 'Wallet account',
            ja: 'ウォレット口座',
            ko: '지갑 계정',
          ),
        'spot' => i18n.t(
            zhHans: '现货账户',
            zhHant: '現貨帳戶',
            en: 'Spot account',
            ja: '現物口座',
            ko: '현물 계정',
          ),
        'funding' => i18n.t(
            zhHans: '资金账户',
            zhHant: '資金帳戶',
            en: 'Funding account',
            ja: '資金口座',
            ko: '펀딩 계정',
          ),
        _ => notProvided,
      };

  /// Arrival estimates of at least one minute round up for display only.
  String arrival(int? seconds) {
    if (seconds == null) return notProvided;
    if (seconds < 60) {
      return i18n.t(
        zhHans: '约$seconds秒',
        zhHant: '約$seconds秒',
        en: 'About $seconds sec',
        ja: '約$seconds秒',
        ko: '약 $seconds초',
      );
    }
    final minutes = seconds ~/ 60 + (seconds % 60 == 0 ? 0 : 1);
    return i18n.t(
      zhHans: '约$minutes分钟',
      zhHant: '約$minutes分鐘',
      en: 'About $minutes min',
      ja: '約$minutes分',
      ko: '약 $minutes분',
    );
  }

  String unlockConfirmations(int? count) => count == null
      ? notProvided
      : i18n.t(
          zhHans: '$count 次区块确认',
          zhHant: '$count 次區塊確認',
          en: '$count block confirmations',
          ja: '$countブロックの承認',
          ko: '$count개 블록 확인',
        );

  String memoHint(bool? required) => switch (required) {
        true => i18n.t(
            zhHans: '必须填写 Memo/Tag',
            zhHant: '必須填寫 Memo/Tag',
            en: 'Memo/Tag is required',
            ja: 'Memo/Tag の入力が必要です',
            ko: 'Memo/Tag 입력이 필요합니다',
          ),
        false => i18n.t(
            zhHans: '无需备注',
            zhHant: '無需備註',
            en: 'No memo is required.',
            ja: 'メモは不要です。',
            ko: '메모는 필요하지 않습니다.',
          ),
        null => i18n.t(
            zhHans: 'Memo/Tag 要求未提供，请先确认',
            zhHant: 'Memo/Tag 要求未提供，請先確認',
            en: 'Memo/Tag requirements were not provided; confirm before sending',
            ja: 'Memo/Tag の要件は未提供です。送金前に確認してください',
            ko: 'Memo/Tag 요구 사항이 제공되지 않았습니다. 전송 전에 확인하세요',
          ),
      };
}
