import 'package:flutter/material.dart';

import '../../data/wallet_history_source_boundary.dart';
import '../../host/wallet_i18n.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../wallet_record_tokens.dart';

/// Describes the limits of the actual client history endpoint.
class WalletRecordSourceNotice extends StatelessWidget {
  const WalletRecordSourceNotice(
      {super.key, required this.source, this.withdrawalsOnly = false});
  final WalletHistorySourceBoundary source;
  final bool withdrawalsOnly;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final message = withdrawalsOnly
        ? i18n.t(
            zhHans: '暂未提供提现记录接口',
            zhHant: '暫未提供提現記錄介面',
            en: 'Withdrawal history is not provided yet',
            ja: '出金履歴はまだ提供されていません',
            ko: '출금 내역은 아직 제공되지 않습니다')
        : i18n.t(
            zhHans:
                '仅显示最近${source.depositRecordLimit}条链上充值事件；时间和实时确认数未提供。完整余额明细及提现记录暂不可用。',
            zhHant:
                '僅顯示最近${source.depositRecordLimit}筆鏈上儲值事件；時間和即時確認數未提供。完整餘額明細及提現記錄暫不可用。',
            en: 'Latest ${source.depositRecordLimit} on-chain deposit events only. Dates and live confirmations are not provided. Complete balance changes and withdrawal history are unavailable.',
            ja: '直近${source.depositRecordLimit}件のオンチェーン入金イベントのみ。日時とリアルタイム承認数は未提供です。全残高履歴と出金履歴は利用できません。',
            ko: '최근 온체인 입금 이벤트 ${source.depositRecordLimit}건만 표시합니다. 시간과 실시간 확인 수는 제공되지 않습니다. 전체 잔액 및 출금 내역은 사용할 수 없습니다.');
    return Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: Text(message,
            key: const ValueKey('wallet-record-source-notice'),
            style: TextStyle(
                fontSize: WalletRecordTokens.caption,
                color: WalletRecordTokens.muted(context))));
  }
}
