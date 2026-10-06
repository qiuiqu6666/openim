import '../wallet_record_models.dart';
import 'wallet_journal_entry.dart';

/// Adapts posted ledger events to the existing wallet row/detail contract.
extension WalletJournalRecordMapper on WalletJournalEntry {
  WalletRecordDto toWalletRecord({
    String counterpartyNickname = '',
    String counterpartyAvatarUrl = '',
  }) =>
      WalletRecordDto(
        id: id,
        type: _recordType,
        // The event is posted even when its associated order is now refunded,
        // expired or failed. Current order state cannot rewrite event history.
        status: WalletRecordStatus.success,
        title: title,
        subTitle: reason.isNotEmpty ? reason : remark,
        amount: amount,
        coin: currency == 'BI99' ? '99' : currency,
        income: direction == 'income',
        network: '',
        fee: '',
        // A counterpartyID is an internal IM identity, not a display account.
        payer: '',
        payee: '',
        groupId: groupID,
        addr: '',
        hash: chainTxID,
        block: '',
        time: '$createdAt',
        orderNo: orderID,
        serverOrderId: orderID,
        memo: reason.isNotEmpty ? reason : remark,
        rpType: switch (bizType) {
          'group_transfer' => 'GROUP_TRANSFER',
          'packet_normal' => 'NORMAL_GROUP',
          'packet_lucky' => 'LUCKY_GROUP',
          'packet_exclusive' => 'EXCLUSIVE',
          _ => '',
        },
        rpMsg: remark,
        createdAt: '$createdAt',
        journal: this,
        counterpartyNickname: counterpartyNickname,
        counterpartyAvatarUrl: counterpartyAvatarUrl,
      );

  WalletRecordType get _recordType {
    if (bizType.startsWith('packet_') || type.startsWith('packet_')) {
      return WalletRecordType.redPacket;
    }
    if (bizType == 'swap' || type.startsWith('swap_')) {
      return WalletRecordType.swap;
    }
    if (bizType == 'deposit' || bizType == 'deposit_reversal') {
      return WalletRecordType.receive;
    }
    if (bizType == 'withdraw') return WalletRecordType.transfer;
    if (bizType == 'transfer' || bizType == 'group_transfer') {
      return direction == 'income'
          ? WalletRecordType.receive
          : WalletRecordType.transfer;
    }
    return direction == 'income'
        ? WalletRecordType.receive
        : direction == 'expense'
            ? WalletRecordType.transfer
            : WalletRecordType.all;
  }
}
