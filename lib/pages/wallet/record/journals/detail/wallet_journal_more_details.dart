import 'package:flutter/material.dart';

import '../../../host/wallet_i18n.dart';
import '../../../host/wallet_chain_explorer.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../../wallet_record_tokens.dart';
import '../wallet_journal_entry.dart';
import '../wallet_journal_presentation.dart';
import 'wallet_journal_detail_field.dart';
import 'wallet_journal_detail_tokens.dart';

/// Ledger-level information stays available without overwhelming the receipt.
class WalletJournalMoreDetails extends StatelessWidget {
  const WalletJournalMoreDetails({super.key, required this.entry});

  final WalletJournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    String label(String zh, String hant, String en, String ja, String ko) =>
        i18n.t(zhHans: zh, zhHant: hant, en: en, ja: ja, ko: ko);
    return ExpansionTile(
      key: const ValueKey('wallet-journal-more-details'),
      maintainState: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      textColor: colors.text,
      collapsedTextColor: colors.text,
      iconColor: colors.subText,
      collapsedIconColor: colors.subText,
      title: Text(label('更多明细', '更多明細', 'More details', 'その他の明細', '추가 내역'),
          style: const TextStyle(fontSize: WalletJournalDetailTokens.body)),
      children: [
        if (entry.title.trim().isNotEmpty)
          WalletJournalDetailField(
            id: 'event-title',
            label: label('原始事件说明', '原始事件說明', 'Original event description',
                '元のイベント説明', '원래 이벤트 설명'),
            value: entry.title,
          ),
        WalletJournalDetailField(
          id: 'operation-amount',
          label: label('操作金额', '操作金額', 'Operation amount', '操作金額', '작업 금액'),
          value: walletJournalAmount(entry.amount, entry.currency),
          amount: true,
        ),
        WalletJournalDetailField(
          id: 'asset-delta',
          label: label('资产变动', '資產變動', 'Asset change', '資産変動', '자산 변동'),
          value: walletJournalAmount(entry.assetDelta, entry.currency,
              signed: true),
          amount: true,
        ),
        WalletJournalDetailField(
          id: 'available-delta',
          label: label('可用余额变动', '可用餘額變動', 'Available change', '利用可能残高の変動',
              '사용 가능 잔액 변동'),
          value: walletJournalAmount(entry.availableDelta, entry.currency,
              signed: true),
          amount: true,
        ),
        WalletJournalDetailField(
          id: 'frozen-delta',
          label:
              label('冻结余额变动', '凍結餘額變動', 'Frozen change', '凍結残高の変動', '동결 잔액 변동'),
          value: walletJournalAmount(entry.frozenDelta, entry.currency,
              signed: true),
          amount: true,
        ),
        WalletJournalDetailField(
          id: 'before-available',
          label: label('变动前可用余额', '變動前可用餘額', 'Available before', '変動前の利用可能残高',
              '변동 전 사용 가능 잔액'),
          value: walletJournalAmount(entry.beforeAvailable, entry.currency),
          amount: true,
        ),
        if (entry.orderID.trim().isNotEmpty)
          WalletJournalDetailField(
            id: 'order-id',
            label: label('订单号', '訂單號', 'Order ID', '注文番号', '주문 번호'),
            value: entry.orderID,
            copy: true,
          ),
        if (entry.orderStatus.trim().isNotEmpty)
          WalletJournalDetailField(
            id: 'current-order-status',
            label: label('订单当前状态', '訂單目前狀態', 'Current order status', '現在の注文状態',
                '현재 주문 상태'),
            value: _currentOrderStatus(entry.orderStatus, i18n),
          ),
        if (entry.counterpartyID.trim().isNotEmpty)
          WalletJournalDetailField(
            id: 'counterparty-id',
            label: label('对方用户ID', '對方使用者ID', 'Counterparty user ID',
                '相手のユーザーID', '상대방 사용자 ID'),
            value: entry.counterpartyID,
            copy: true,
          ),
        if (entry.groupID.trim().isNotEmpty)
          WalletJournalDetailField(
            id: 'group-id',
            label: label('群ID', '群組ID', 'Group ID', 'グループID', '그룹 ID'),
            value: entry.groupID,
            copy: true,
          ),
        if (entry.chainTxID.trim().isNotEmpty)
          WalletJournalDetailField(
            id: 'chain-tx-id',
            label: label('交易哈希', '交易雜湊', 'Transaction hash', '取引ハッシュ', '거래 해시'),
            value: entry.chainTxID,
            copy: true,
            valueColor: colors.blue,
            onTap: () => openWalletTronTransaction(context, entry.chainTxID),
          ),
        if (entry.reason.trim().isNotEmpty)
          WalletJournalDetailField(
            id: 'reason',
            label: label('调整说明', '調整說明', 'Adjustment reason', '調整理由', '조정 사유'),
            value: entry.reason,
          ),
        if (entry.orderStatus.trim().isNotEmpty ||
            entry.orderID.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
            child: Text(
              label(
                '同一订单可能包含多条流水；订单状态为当前状态，不代表该流水发生时的状态。',
                '同一訂單可能包含多筆流水；訂單狀態為目前狀態，不代表該流水發生時的狀態。',
                'An order can have multiple journal entries. Order status is current, not the status when this event occurred.',
                '同じ注文に複数の明細が含まれる場合があります。注文状態は現在の状態であり、このイベント発生時の状態ではありません。',
                '한 주문에 여러 내역이 포함될 수 있습니다. 주문 상태는 현재 상태이며 이벤트 발생 당시 상태가 아닙니다.',
              ),
              key: const ValueKey('wallet-journal-order-status-explanation'),
              style: TextStyle(
                  color: WalletRecordTokens.muted(context),
                  fontSize: WalletJournalDetailTokens.caption),
            ),
          ),
      ],
    );
  }
}

String _currentOrderStatus(String status, AppI18n i18n) => switch (status) {
      'refunded' => i18n.t(
          zhHans: '已退回', zhHant: '已退回', en: 'Refunded', ja: '返金済み', ko: '환불됨'),
      'done' || 'completed' || 'success' || 'settled' => i18n.t(
          zhHans: '已完成', zhHant: '已完成', en: 'Completed', ja: '完了', ko: '완료됨'),
      'open' => i18n.t(
          zhHans: '待领取',
          zhHant: '待領取',
          en: 'Awaiting collection',
          ja: '受取待ち',
          ko: '수령 대기'),
      'withdraw_pending' => i18n.t(
          zhHans: '等待审核',
          zhHant: '等待審核',
          en: 'Awaiting review',
          ja: '審査待ち',
          ko: '심사 대기'),
      'withdraw_approved' => i18n.t(
          zhHans: '等待出款',
          zhHant: '等待出款',
          en: 'Awaiting payment',
          ja: '送金待ち',
          ko: '지급 대기'),
      'withdraw_done' => i18n.t(
          zhHans: '已登记出款',
          zhHant: '已登記出款',
          en: 'Payment recorded',
          ja: '送金登録済み',
          ko: '지급 기록됨'),
      'withdraw_failed' => i18n.t(
          zhHans: '已退回',
          zhHant: '已退回',
          en: 'Returned',
          ja: '返金済み',
          ko: '환불됨'),
      'pending' || 'processing' => i18n.t(
          zhHans: '处理中',
          zhHant: '處理中',
          en: 'Processing',
          ja: '処理中',
          ko: '처리 중'),
      'failed' =>
        i18n.t(zhHans: '失败', zhHant: '失敗', en: 'Failed', ja: '失敗', ko: '실패'),
      _ => status,
    };
