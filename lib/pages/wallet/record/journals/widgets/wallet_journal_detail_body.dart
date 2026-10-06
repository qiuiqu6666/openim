import 'package:flutter/material.dart';

import '../../../host/wallet_i18n.dart';
import '../../../host/wallet_chain_explorer.dart';
import '../../../wallet_time.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../../wallet_record_tokens.dart';
import '../detail/wallet_journal_detail_field.dart';
import '../detail/wallet_journal_detail_header.dart';
import '../detail/wallet_journal_detail_tokens.dart';
import '../wallet_journal_entry.dart';
import '../wallet_journal_presentation.dart';

/// A compact receipt for a posted event. The screen owns order navigation.
class WalletJournalDetailBody extends StatelessWidget {
  const WalletJournalDetailBody({
    super.key,
    required this.entry,
    required this.coinLogo,
    this.counterpartyNickname = '',
    this.counterpartyAvatarUrl = '',
    this.counterpartyAccount = '',
    this.onOpenOrder,
  });

  final WalletJournalEntry entry;
  final Widget coinLogo;
  final String counterpartyNickname;
  final String counterpartyAvatarUrl;
  final String counterpartyAccount;
  final VoidCallback? onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    String label(String zh, String hant, String en, String ja, String ko) =>
        i18n.t(zhHans: zh, zhHant: hant, en: en, ja: ja, ko: ko);
    final account = counterpartyAccount.trim();
    final nickname = counterpartyNickname.trim();
    final deposit =
        const {'deposit', 'deposit_reversal'}.contains(entry.bizType) ||
            const {'deposit', 'deposit_reversal'}.contains(entry.type);
    final withdrawal =
        entry.bizType == 'withdraw' || entry.type.startsWith('withdraw_');
    final swap = entry.bizType == 'swap' ||
        const {'swap_in', 'swap_out'}.contains(entry.type);
    final fields = <Widget>[
      WalletJournalDetailField(
        id: 'time',
        label: label('支付时间', '支付時間', 'Payment time', '支払日時', '결제 시간'),
        value: formatWalletApiDateTime(
          DateTime.fromMillisecondsSinceEpoch(entry.createdAt, isUtc: true),
          pattern: 'yyyy-MM-dd HH:mm:ss',
        ),
      ),
      WalletJournalDetailField(
        id: 'transaction-type',
        label: label('交易类型', '交易類型', 'Transaction type', '取引種別', '거래 유형'),
        value: entry.direction == 'neutral'
            ? label('中性', '中性', 'Neutral', '中立', '중립')
            : walletJournalDirectionLabel(entry, i18n),
      ),
      if (!deposit && !withdrawal && !swap)
        WalletJournalDetailField(
          id: account.isEmpty ? 'counterparty-user' : 'counterparty-account',
          label: account.isEmpty
              ? label('对方用户', '對方使用者', 'Counterparty', '相手', '상대방')
              : label(
                  '对方账户', '對方帳戶', 'Counterparty account', '相手のアカウント', '상대방 계정'),
          value: account.isNotEmpty
              ? account
              : nickname.isNotEmpty
                  ? nickname
                  : '--',
        ),
      WalletJournalDetailField(
        id: 'journal-id',
        label: label('交易号', '交易號', 'Transaction ID', '取引番号', '거래 번호'),
        value: entry.id,
        copy: true,
      ),
      if ((deposit || withdrawal) && entry.chainTxID.trim().isNotEmpty)
        WalletJournalDetailField(
          id: 'chain-tx-id',
          label: label('交易哈希', '交易雜湊', 'Transaction hash', '取引ハッシュ', '거래 해시'),
          value: entry.chainTxID,
          copy: true,
          valueColor: colors.blue,
          onTap: () => openWalletTronTransaction(context, entry.chainTxID),
        ),
      if ((deposit || withdrawal) && entry.toAddress.trim().isNotEmpty)
        WalletJournalDetailField(
          id: 'to-address',
          label: withdrawal
              ? label('提现地址', '提現地址', 'Withdrawal address', '出金先アドレス', '출금 주소')
              : label('转入地址', '轉入地址', 'Receiving address', '入金先アドレス', '입금 주소'),
          value: entry.toAddress,
          copy: true,
        ),
      WalletJournalDetailField(
        id: 'remark',
        label: label('备注', '備註', 'Remark', '備考', '비고'),
        value: entry.remark.trim().isEmpty ? '--' : entry.remark,
      ),
    ];
    Widget divider() => Divider(
        height: WalletRecordTokens.divider,
        thickness: WalletJournalDetailTokens.divider,
        color: colors.line);
    return ColoredBox(
      color: colors.bg,
      child: ListView(
        key: const ValueKey('wallet-journal-detail-scroll'),
        padding: const EdgeInsets.all(WalletJournalDetailTokens.outerInset),
        children: [
          Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: WalletRecordTokens.maxWidth),
              child: Material(
                key: const ValueKey('wallet-journal-detail-card'),
                color: colors.card,
                borderRadius:
                    BorderRadius.circular(WalletJournalDetailTokens.radius),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: WalletJournalDetailTokens.cardInset,
                    right: WalletJournalDetailTokens.cardInset,
                    bottom: WalletJournalDetailTokens.rowPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WalletJournalDetailHeader(
                        entry: entry,
                        coinLogo: coinLogo,
                        counterpartyNickname: counterpartyNickname,
                        counterpartyAvatarUrl: counterpartyAvatarUrl,
                      ),
                      if (entry.orderID.trim().isNotEmpty &&
                          onOpenOrder != null) ...[
                        InkWell(
                          key: const ValueKey('wallet-journal-open-order'),
                          onTap: onOpenOrder,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                minHeight: WalletRecordTokens.minTap),
                            child: WalletJournalDetailField(
                              id: 'linked-order',
                              label: label('关联账单', '關聯帳單', 'Related bill',
                                  '関連明細', '연결된 청구서'),
                              value: label('查看账单详情', '查看帳單詳情',
                                  'View bill details', '請求明細を表示', '청구 내역 보기'),
                              valueColor: colors.blue,
                            ),
                          ),
                        ),
                        divider(),
                      ],
                      ...fields,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
