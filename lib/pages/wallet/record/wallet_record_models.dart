import '../host/wallet_i18n.dart';
import 'journals/wallet_journal_entry.dart';

enum WalletRecordType {
  all,
  receive,
  transfer,
  redPacket,
  swap,
}

enum HistoryRecordFilter {
  all,
  chainWithdraw,
  chainDeposit,
  internalDeposit,
  internalWithdraw,
  redPacket,
  redPacketRefund,
  transfer,
  transferRefund,
}

enum WalletRecordStatus {
  success,
  pending,
  failed,
}

extension WalletRecordTypeX on WalletRecordType {
  String get txt {
    switch (this) {
      case WalletRecordType.all:
        return AppI18n.current.t(
          zhHans: '全部',
          zhHant: '全部',
          en: 'All',
          ja: 'すべて',
          ko: '전체',
        );
      case WalletRecordType.receive:
        return AppI18n.current.t(
          zhHans: '收款',
          zhHant: '收款',
          en: 'Receive',
          ja: '受取',
          ko: '수취',
        );
      case WalletRecordType.transfer:
        return AppI18n.current.t(
          zhHans: '转账',
          zhHant: '轉帳',
          en: 'Transfer',
          ja: '送金',
          ko: '송금',
        );
      case WalletRecordType.redPacket:
        return AppI18n.current.t(
          zhHans: '红包',
          zhHant: '紅包',
          en: 'Red Packet',
          ja: '紅包',
          ko: '레드패킷',
        );
      case WalletRecordType.swap:
        return AppI18n.current.t(
          zhHans: '闪兑',
          zhHant: '閃兌',
          en: 'Swap',
          ja: 'スワップ',
          ko: '스왑',
        );
    }
  }
}

extension HistoryRecordFilterX on HistoryRecordFilter {
  String get txt {
    switch (this) {
      case HistoryRecordFilter.all:
        return AppI18n.current.t(
          zhHans: '全部',
          zhHant: '全部',
          en: 'All',
          ja: 'すべて',
          ko: '전체',
        );
      case HistoryRecordFilter.chainWithdraw:
        return AppI18n.current.t(
          zhHans: '链上提币',
          zhHant: '鏈上提幣',
          en: 'On-chain Withdrawal',
          ja: 'オンチェーン出金',
          ko: '온체인 출금',
        );
      case HistoryRecordFilter.chainDeposit:
        return AppI18n.current.t(
          zhHans: '链上充币',
          zhHant: '鏈上充幣',
          en: 'On-chain Deposit',
          ja: 'オンチェーン入金',
          ko: '온체인 입금',
        );
      case HistoryRecordFilter.internalDeposit:
        return AppI18n.current.t(
          zhHans: '内部充币',
          zhHant: '內部充幣',
          en: 'Internal Deposit',
          ja: '内部入金',
          ko: '내부 입금',
        );
      case HistoryRecordFilter.internalWithdraw:
        return AppI18n.current.t(
          zhHans: '内部提币',
          zhHant: '內部提幣',
          en: 'Internal Withdrawal',
          ja: '内部出金',
          ko: '내부 출금',
        );
      case HistoryRecordFilter.redPacket:
        return AppI18n.current.t(
          zhHans: '红包',
          zhHant: '紅包',
          en: 'Red Packet',
          ja: '紅包',
          ko: '레드패킷',
        );
      case HistoryRecordFilter.redPacketRefund:
        return AppI18n.current.t(
          zhHans: '红包退款',
          zhHant: '紅包退款',
          en: 'Red Packet Refund',
          ja: '紅包返金',
          ko: '레드패킷 환불',
        );
      case HistoryRecordFilter.transfer:
        return AppI18n.current.t(
          zhHans: '转账',
          zhHant: '轉帳',
          en: 'Transfer',
          ja: '送金',
          ko: '송금',
        );
      case HistoryRecordFilter.transferRefund:
        return AppI18n.current.t(
          zhHans: '转账退款',
          zhHant: '轉帳退款',
          en: 'Transfer Refund',
          ja: '送金返金',
          ko: '송금 환불',
        );
    }
  }
}

extension WalletRecordStatusX on WalletRecordStatus {
  String get txt {
    switch (this) {
      case WalletRecordStatus.success:
        return AppI18n.current.t(
          zhHans: '成功',
          zhHant: '成功',
          en: 'Success',
          ja: '成功',
          ko: '성공',
        );
      case WalletRecordStatus.pending:
        return AppI18n.current.t(
          zhHans: '处理中',
          zhHant: '處理中',
          en: 'Processing',
          ja: '処理中',
          ko: '처리 중',
        );
      case WalletRecordStatus.failed:
        return AppI18n.current.t(
          zhHans: '失败',
          zhHant: '失敗',
          en: 'Failed',
          ja: '失敗',
          ko: '실패',
        );
    }
  }
}

class WalletRecordDto {
  final WalletJournalEntry? journal;
  final String counterpartyNickname;
  final String counterpartyAvatarUrl;
  final String id;
  final WalletRecordType type;
  final WalletRecordStatus status;

  final String title;
  final String subTitle;
  final String amount;
  final String coin;
  final bool income;

  final String network;
  final String fee;
  final String payer;
  final String payee;
  final String senderAvatar;
  final String receiverAvatar;
  final String groupId;
  final String groupName;
  final String groupAvatar;
  final String addr;
  final String hash;
  final String block;
  final String time;
  final String orderNo;
  final String serverOrderId;
  final String clientOrderId;
  final String memo;

  final String rpType;
  final String rpCnt;
  final String rpTotal;
  final String rpClaim;
  final String rpMsg;
  final String rpStatus;
  final String createdAt;
  final String expiredAt;

  const WalletRecordDto({
    this.journal,
    this.counterpartyNickname = '',
    this.counterpartyAvatarUrl = '',
    required this.id,
    required this.type,
    required this.status,
    required this.title,
    required this.subTitle,
    required this.amount,
    required this.coin,
    required this.income,
    required this.network,
    required this.fee,
    required this.payer,
    required this.payee,
    this.senderAvatar = '',
    this.receiverAvatar = '',
    this.groupId = '',
    this.groupName = '',
    this.groupAvatar = '',
    required this.addr,
    required this.hash,
    required this.block,
    required this.time,
    required this.orderNo,
    this.serverOrderId = '',
    this.clientOrderId = '',
    required this.memo,
    this.rpType = '',
    this.rpCnt = '',
    this.rpTotal = '',
    this.rpClaim = '',
    this.rpMsg = '',
    this.rpStatus = '',
    this.createdAt = '',
    this.expiredAt = '',
  });
}

extension WalletRecordDtoX on WalletRecordDto {
  bool get isChainDeposit => journal != null
      ? journal!.bizType == 'deposit'
      : type == WalletRecordType.receive &&
          (network.toUpperCase().contains('TRC20') ||
              network.toUpperCase().contains('BTC') ||
              network.toUpperCase().contains('ERC20') ||
              title.contains('充值'));

  bool get isChainWithdraw => journal != null
      ? journal!.bizType == 'withdraw' ||
          (journal!.bizType == 'withdraw_fee_refund' &&
              journal!.chainTxID.isNotEmpty)
      : type == WalletRecordType.transfer &&
          (title.contains('提现') ||
              (addr.trim().isNotEmpty && payee.trim() == '外部地址'));

  bool get isInternalReceive => journal != null
      ? journal!.type == 'transfer_received'
      : type == WalletRecordType.receive &&
          !isChainDeposit &&
          !title.contains('领取红包');

  bool get isInternalTransfer => journal != null
      ? journal!.type == 'transfer_sent'
      : type == WalletRecordType.transfer &&
          !isChainWithdraw &&
          !title.contains('红包');

  bool get isRedPacketReceive => journal != null
      ? journal!.type == 'packet_received'
      : type == WalletRecordType.redPacket && title.contains('领取');

  bool get isRedPacketSend => journal != null
      ? const {'packet_sent', 'packet_freeze', 'packet_settlement'}
          .contains(journal!.type)
      : type == WalletRecordType.redPacket &&
          !isRedPacketReceive &&
          !isRedPacketRefund;

  bool get isRedPacketRefund => journal != null
      ? journal!.type == 'packet_refund'
      : type == WalletRecordType.redPacket &&
          (title.contains('退回') || rpStatus.contains('退款'));

  bool get isGroupTransfer => journal != null
      ? journal!.bizType == 'group_transfer'
      : rpType.trim().toUpperCase() == 'GROUP_TRANSFER' &&
          (isRedPacketSend || isRedPacketReceive);

  bool get isGroupRedPacket => journal != null
      ? const {'packet_normal', 'packet_lucky'}.contains(journal!.bizType)
      : (rpType.trim().toUpperCase() == 'NORMAL_GROUP' ||
              rpType.trim().toUpperCase() == 'LUCKY_GROUP') &&
          (isRedPacketSend || isRedPacketReceive);

  bool get isSwap => type == WalletRecordType.swap;
}
