import 'dart:convert';

import '../res/strings.dart';

/// A server-created funds message is an order reference, never proof of funds
/// received or permission to claim. Opening it must load the actual order.
class FundMessageData {
  const FundMessageData({
    required this.orderID,
    required this.biz,
    required this.currency,
    required this.amount,
    required this.status,
    this.remark = '',
  });

  final String orderID;
  final String biz;
  final String currency;
  final String amount;
  final String status;
  final String remark;

  bool get isPacket => biz.startsWith('packet_');
  bool get isTransfer => biz == 'transfer' || biz == 'group_transfer';
  String get currencyLabel => currency == 'BI99' ? '99BI' : currency;

  /// Pad the displayed cents while preserving the server's full precision.
  String get displayAmount {
    final parts = amount.split('.');
    return '${parts.first}.${(parts.length == 1 ? '' : parts[1]).padRight(2, '0')}';
  }

  String get typeLabel => switch (biz) {
        'packet_exclusive' => StrRes.fundExclusivePacket,
        'packet_lucky' => StrRes.fundLuckyPacket,
        'packet_normal' => StrRes.fundPacket,
        'group_transfer' => StrRes.fundGroupTransfer,
        _ => StrRes.fundTransfer,
      };

  FundMessageData copyWith({String? status, String? remark}) => FundMessageData(
        orderID: orderID,
        biz: biz,
        currency: currency,
        amount: amount,
        status: status ?? this.status,
        remark: remark == null ? this.remark : normalizeRemark(remark),
      );

  /// Remarks are optional display text. Invalid optional text must not hide
  /// an otherwise valid legacy order reference or expand custom recognition.
  static String normalizeRemark(Object? value) {
    if (value is! String) return '';
    final text = value.trim();
    return text.runes.length <= 12 ? text : '';
  }

  static const _businesses = {
    'transfer',
    'group_transfer',
    'packet_exclusive',
    'packet_normal',
    'packet_lucky',
  };
  static const _statuses = {'open', 'done', 'refunded'};
  static final _amountPattern = RegExp(r'^\d+(?:\.\d+)?$');

  /// Recognize only the documented top-level funds payload. Unknown custom
  /// messages and malformed financial values keep the normal fallback view.
  static FundMessageData? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final orderID = json['orderID'];
      final biz = json['biz'];
      final currency = json['currency'];
      final amount = json['amount'];
      final status = json['status'];
      if (orderID is! String ||
          orderID.trim().isEmpty ||
          biz is! String ||
          !_businesses.contains(biz) ||
          currency is! String ||
          !{'USDT', 'TRX', 'BI99'}.contains(currency) ||
          amount is! String ||
          !_amountPattern.hasMatch(amount) ||
          !RegExp(r'[1-9]').hasMatch(amount) ||
          status is! String ||
          !_statuses.contains(status)) {
        return null;
      }
      final decimalPlaces =
          amount.contains('.') ? amount.split('.').last.length : 0;
      if (decimalPlaces > (currency == 'BI99' ? 2 : 6)) return null;
      return FundMessageData(
        orderID: orderID.trim(),
        biz: biz,
        currency: currency,
        amount: amount,
        status: status,
        remark: normalizeRemark(json['remark']),
      );
    } on FormatException {
      return null;
    }
  }
}
