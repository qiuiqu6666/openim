// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
/// Unified /admin/reports/user-flow entry. Amount is always signed.
class SangongAccountFlowEntry {
  const SangongAccountFlowEntry(
      {required this.ledgerId,
      required this.type,
      required this.amount,
      required this.balanceAfter,
      this.userId,
      this.imUserId = '',
      this.nickname = '',
      this.sessionId,
      this.periodNo,
      this.refType,
      this.refId,
      this.note = '',
      this.operator = '',
      this.createdAt = ''});
  final int ledgerId;
  final int? userId;
  final String imUserId, nickname, type, note, operator, createdAt;
  final int amount, balanceAfter;
  final int? sessionId, refId;
  final int? periodNo;
  final String? refType;

  static const betTypes = {
    'bet_hold',
    'bet_recall',
    'bet_void',
    'bet_restart',
    'settle_win',
    'settle_banker',
    'settle_void'
  };
  static const creditTypes = {'admin_credit', 'credit', 'user_transfer_in'};
  static const debitTypes = {'admin_debit', 'debit', 'user_transfer_out'};
  bool get isBet => betTypes.contains(type);
  bool get isCredit => creditTypes.contains(type);
  bool get isDebit => debitTypes.contains(type);
  bool get isScoreTransfer => isCredit || isDebit;

  String get label =>
      const {
        'bet_hold': '下注扣款',
        'bet_recall': '撤回下注',
        'bet_void': '作废退还',
        'bet_restart': '重开退还',
        'settle_win': '结算派彩',
        'settle_banker': '庄家结算',
        'settle_void': '结算冲正',
        'admin_credit': '上分',
        'credit': '上分',
        'admin_debit': '下分',
        'debit': '下分',
        'user_transfer_in': '下级收款',
        'user_transfer_out': '向下级划转',
      }[type] ??
      type;

  static int? _integer(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');
  factory SangongAccountFlowEntry.fromJson(Map<String, dynamic> json) =>
      SangongAccountFlowEntry(
        ledgerId: _integer(json['ledgerId']) ?? 0,
        userId: _integer(json['userId']),
        imUserId: json['imUserId']?.toString() ?? '',
        nickname: json['nickname']?.toString() ?? '',
        sessionId: _integer(json['sessionId']),
        periodNo: _integer(json['periodNo'] ?? json['period_no']),
        type: json['type']?.toString().trim().toLowerCase() ?? '',
        amount: _integer(json['amount']) ?? 0,
        balanceAfter: _integer(json['balanceAfter']) ?? 0,
        refType: json['refType']?.toString(),
        refId: _integer(json['refId']),
        note: json['note']?.toString() ?? '',
        operator: json['operator']?.toString() ?? '',
        createdAt: json['createdAt']?.toString() ?? '',
      );
}
