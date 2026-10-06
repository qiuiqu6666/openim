import '../../host/wallet_i18n.dart';

const walletJournalBizTypes = {
  'transfer': ['transfer_sent', 'transfer_received'],
  'group_transfer': ['transfer_sent', 'transfer_received'],
  'packet_exclusive': [
    'packet_sent',
    'packet_received',
    'packet_freeze',
    'packet_settlement',
    'packet_refund'
  ],
  'packet_normal': [
    'packet_sent',
    'packet_received',
    'packet_freeze',
    'packet_settlement',
    'packet_refund'
  ],
  'packet_lucky': [
    'packet_sent',
    'packet_received',
    'packet_freeze',
    'packet_settlement',
    'packet_refund'
  ],
  'withdraw': ['withdraw_freeze', 'withdraw_settlement', 'withdraw_refund'],
  'swap': ['swap_out', 'swap_in'],
  'deposit': ['deposit'],
  'deposit_reversal': ['deposit_reversal'],
  'admin_adjust': ['admin_adjust'],
  'admin_grant': ['admin_grant'],
  'live_tip': ['live_tip_sent', 'live_tip_received'],
};

const _labels = <String, (String, String, String)>{
  'all': ('全部', '全部', 'All'),
  'transfer': ('转账', '轉帳', 'Transfer'),
  'group_transfer': ('群转账', '群轉帳', 'Group transfer'),
  'packet_exclusive': ('专属红包', '專屬紅包', 'Exclusive packet'),
  'packet_normal': ('普通群红包', '普通群紅包', 'Group packet'),
  'packet_lucky': ('拼手气红包', '拼手氣紅包', 'Lucky packet'),
  'withdraw': ('提现', '提現', 'Withdrawal'),
  'swap': ('闪兑', '閃兌', 'Swap'),
  'deposit': ('链上充值', '鏈上充值', 'Deposit'),
  'deposit_reversal': ('充值撤销', '充值撤銷', 'Deposit reversal'),
  'admin_adjust': ('人工调整', '人工調整', 'Manual adjustment'),
  'admin_grant': ('平台赠送', '平台贈送', 'Platform grant'),
  'live_tip': ('直播打赏', '直播打賞', 'Live tip'),
  'transfer_sent': ('转账支出', '轉帳支出', 'Transfer sent'),
  'transfer_received': ('收到转账', '收到轉帳', 'Transfer received'),
  'packet_sent': ('发红包', '發紅包', 'Packet sent'),
  'packet_received': ('收到红包', '收到紅包', 'Packet received'),
  'packet_freeze': ('红包冻结', '紅包凍結', 'Packet freeze'),
  'packet_settlement': ('红包领取扣款', '紅包領取扣款', 'Packet settlement'),
  'packet_refund': ('红包退回', '紅包退回', 'Packet refund'),
  'withdraw_freeze': ('提现冻结', '提現凍結', 'Withdrawal freeze'),
  'withdraw_settlement': ('提现扣款', '提現扣款', 'Withdrawal settlement'),
  'withdraw_refund': ('提现退回', '提現退回', 'Withdrawal refund'),
  'swap_out': ('闪兑支出', '閃兌支出', 'Swap out'),
  'swap_in': ('闪兑转入', '閃兌轉入', 'Swap in'),
  'live_tip_sent': ('打赏支出', '打賞支出', 'Tip sent'),
  'live_tip_received': ('收到打赏', '收到打賞', 'Tip received'),
  'income': ('收入', '收入', 'Income'),
  'expense': ('支出', '支出', 'Expense'),
  'freeze': ('冻结', '凍結', 'Freeze'),
  'unfreeze': ('解冻', '解凍', 'Unfreeze'),
  'neutral': ('无数量变动', '無數量變動', 'No asset change'),
};

String walletJournalFilterLabel(String value, AppI18n i18n) {
  final label = _labels[value];
  if (label == null) return value;
  return i18n.t(
      zhHans: label.$1,
      zhHant: label.$2,
      en: label.$3,
      ja: label.$3,
      ko: label.$3);
}
