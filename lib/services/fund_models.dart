/// API currency codes and their smallest accounting units.
enum FundCurrency {
  usdt('USDT', 'USDT', 6),
  trx('TRX', 'TRX', 6),
  bi99('BI99', '99BI', 2);

  const FundCurrency(this.code, this.displayName, this.decimals);
  final String code;
  final String displayName;
  final int decimals;

  static FundCurrency parse(String value) => values.firstWhere(
        (currency) => currency.code == value,
        orElse: () => throw const FormatException('Unsupported fund currency'),
      );
}

enum FundScene { single, group, internal }

/// Request remarks use Unicode code points, rather than UTF-16 code units or
/// grapheme clusters. Empty packet remarks are defaulted by the server.
abstract final class FundRemark {
  static const maxCodePoints = 12;
  static const defaultPacket = '恭喜发财，大吉大利';

  static String normalize(String value) {
    final normalized = value.trim();
    if (normalized.runes.length > maxCodePoints) {
      throw const FormatException('备注最多支持 12 个 Unicode 码点');
    }
    return normalized;
  }
}

enum FundPacketBiz {
  exclusive('packet_exclusive'),
  normal('packet_normal'),
  lucky('packet_lucky');

  const FundPacketBiz(this.code);
  final String code;
}

/// Decimal money is parsed into integer units, never through a double.
class FundAmount implements Comparable<FundAmount> {
  const FundAmount._(this.currency, this.units);

  factory FundAmount.parse(String value, FundCurrency currency) {
    final input = value.trim();
    if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(input)) {
      throw const FormatException('请输入有效金额');
    }
    final parts = input.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > currency.decimals) {
      throw FormatException(
          '${currency.displayName} 最多支持 ${currency.decimals} 位小数');
    }
    return FundAmount._(
      currency,
      BigInt.parse(parts[0]) * _scale(currency) +
          BigInt.parse(fraction.padRight(currency.decimals, '0')),
    );
  }

  factory FundAmount.zero(FundCurrency currency) =>
      FundAmount._(currency, BigInt.zero);

  final FundCurrency currency;
  final BigInt units;
  bool get isPositive => units > BigInt.zero;

  static BigInt _scale(FundCurrency currency) =>
      BigInt.from(10).pow(currency.decimals);

  String get decimal {
    final scale = _scale(currency);
    final absolute = units.abs();
    final sign = units.isNegative ? '-' : '';
    final whole = absolute ~/ scale;
    final fraction = (absolute % scale)
        .toString()
        .padLeft(currency.decimals, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
  }

  /// Payment presentation pads cents without rounding supported precision.
  /// Wire amounts continue using [decimal].
  String get displayDecimal {
    final parts = decimal.split('.');
    return '${parts.first}.${(parts.length == 1 ? '' : parts[1]).padRight(2, '0')}';
  }

  FundAmount multipliedBy(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return FundAmount._(currency, units * BigInt.from(count));
  }

  @override
  int compareTo(FundAmount other) {
    if (currency != other.currency) {
      throw ArgumentError('Cannot compare different currencies');
    }
    return units.compareTo(other.units);
  }

  @override
  String toString() => decimal;

  @override
  bool operator ==(Object other) =>
      other is FundAmount && currency == other.currency && units == other.units;

  @override
  int get hashCode => Object.hash(currency, units);
}

class FundBalance {
  const FundBalance({
    required this.currency,
    required this.available,
    required this.frozen,
  });

  factory FundBalance.fromJson(Map<String, dynamic> json,
      {bool allowNegativeAvailable = false}) {
    final currency = FundCurrency.parse(_requiredString(json, 'currency'));
    final rawAvailable = _requiredString(json, 'available');
    // A reversed chain deposit may leave an already spent balance negative.
    // Spending amounts continue to use the unsigned FundAmount.parse contract.
    final negative = allowNegativeAvailable && rawAvailable.startsWith('-');
    if (negative && !RegExp(r'^-\d+(?:\.\d+)?$').hasMatch(rawAvailable)) {
      throw const FormatException('Invalid fund balance');
    }
    final available = FundAmount.parse(
        negative ? rawAvailable.substring(1) : rawAvailable, currency);
    return FundBalance(
      currency: currency,
      available:
          negative ? FundAmount._(currency, -available.units) : available,
      frozen: FundAmount.parse(_requiredString(json, 'frozen'), currency),
    );
  }

  final FundCurrency currency;
  final FundAmount available;
  final FundAmount frozen;
}

class FundShare {
  const FundShare({
    required this.index,
    required this.amount,
    this.claimerID = '',
    this.claimedAt,
  });

  factory FundShare.fromJson(
    Map<String, dynamic> json,
    FundCurrency currency, {
    int defaultIndex = 0,
  }) =>
      FundShare(
        index: _integer(json['index']) ?? defaultIndex,
        amount: FundAmount.parse(_requiredString(json, 'amount'), currency),
        claimerID: _optionalString(json, 'claimerID', 'claimer_id'),
        claimedAt: _date(json['claimedAt'] ?? json['claimed_at']),
      );

  final int index;
  final FundAmount amount;
  final String claimerID;
  final DateTime? claimedAt;
  bool get isClaimed => claimerID.isNotEmpty;
}

/// The server order, rather than the message card, is authoritative.
class FundOrder {
  const FundOrder({
    required this.orderID,
    required this.biz,
    required this.scene,
    required this.currency,
    required this.amount,
    required this.status,
    this.clientOrderID = '',
    this.senderID = '',
    this.recvID = '',
    this.groupID = '',
    this.shareAmount,
    this.shareCount = 0,
    this.shares = const [],
    this.expireAt,
    this.createdAt,
    this.remark = '',
    this.recipientType = '',
    this.recipient = '',
    this.recipientAreaCode = '',
    this.fee = '0',
  });

  factory FundOrder.fromJson(Map<String, dynamic> json) {
    final currency = FundCurrency.parse(_requiredString(json, 'currency'));
    final biz = _requiredString(json, 'biz');
    if (!const {
      'transfer',
      'group_transfer',
      'packet_exclusive',
      'packet_normal',
      'packet_lucky',
    }.contains(biz)) {
      throw const FormatException('Unsupported fund order');
    }
    final status = _requiredString(json, 'status');
    if (!const {'done', 'open', 'refunded'}.contains(status)) {
      throw const FormatException('Unsupported fund order status');
    }
    final groupID = _optionalString(json, 'groupID', 'group_id');
    final sceneValue = json['scene'];
    if (sceneValue != null &&
        !FundScene.values.any((scene) => scene.name == sceneValue)) {
      throw const FormatException('Unsupported fund scene');
    }
    final scene = sceneValue == 'internal'
        ? FundScene.internal
        : sceneValue == 'group' ||
                (sceneValue == null &&
                    (groupID.isNotEmpty || biz == 'group_transfer'))
            ? FundScene.group
            : FundScene.single;
    if (scene == FundScene.internal &&
        biz != 'transfer' &&
        biz != 'group_transfer') {
      throw const FormatException('Unsupported internal fund order');
    }
    final rawShares = json['shares'];
    if (rawShares != null && rawShares is! List) {
      throw const FormatException('Invalid fund shares');
    }
    final shares = <FundShare>[];
    for (final value in (rawShares as List? ?? const [])) {
      if (value is! Map) throw const FormatException('Invalid fund share');
      shares.add(FundShare.fromJson(Map<String, dynamic>.from(value), currency,
          defaultIndex: shares.length));
    }
    final shareAmount = json['shareAmount'] ?? json['share_amount'];
    if (shareAmount != null && shareAmount is! String) {
      throw const FormatException('Fund amounts must be decimal strings');
    }
    if (json.containsKey('remark') && json['remark'] is! String) {
      throw const FormatException('Invalid fund remark');
    }
    return FundOrder(
      orderID: _requiredString(json, 'orderID', 'order_id'),
      clientOrderID: _optionalString(json, 'clientOrderID', 'client_order_id'),
      biz: biz,
      scene: scene,
      currency: currency,
      amount: FundAmount.parse(_requiredString(json, 'amount'), currency),
      status: status,
      senderID: _optionalString(json, 'senderID', 'sender_id'),
      recvID: _optionalString(json, 'recvID', 'recv_id'),
      groupID: groupID,
      shareAmount: shareAmount == null
          ? null
          : FundAmount.parse(shareAmount as String, currency),
      shareCount:
          _integer(json['shareCount'] ?? json['share_count']) ?? shares.length,
      shares: List.unmodifiable(shares),
      expireAt: _date(json['expireAt'] ?? json['expire_at']),
      createdAt: _date(json['createdAt'] ?? json['created_at']),
      remark: json['remark'] as String? ?? '',
      recipientType: _optionalString(json, 'recipientType'),
      recipient: _optionalString(json, 'recipient'),
      recipientAreaCode: _optionalString(json, 'recipientAreaCode'),
      fee: _optionalString(json, 'fee').isEmpty ? '0' : json['fee'] as String,
    );
  }

  final String orderID;
  final String clientOrderID;
  final String biz;
  final FundScene scene;
  final FundCurrency currency;
  final FundAmount amount;
  final String senderID;
  final String recvID;
  final String groupID;
  final String status;
  final FundAmount? shareAmount;
  final int shareCount;
  final List<FundShare> shares;
  final DateTime? expireAt;
  final DateTime? createdAt;
  final String remark;
  final String recipientType, recipient, recipientAreaCode, fee;

  bool get isPacket => biz.startsWith('packet_');
  bool get isTransfer => biz == 'transfer' || biz == 'group_transfer';
  bool get requiresClaim =>
      scene == FundScene.group &&
      (biz == 'packet_normal' || biz == 'packet_lucky');
  bool get isOpen => status == 'open';
  bool get isRefunded => status == 'refunded';
  bool get isExpired => expireAt != null && !expireAt!.isAfter(DateTime.now());

  FundShare? claimedShareFor(String userID) {
    if (userID.isEmpty) return null;
    for (final share in shares) {
      if (share.claimerID == userID) return share;
    }
    return null;
  }
}

class FundClaimResult {
  const FundClaimResult({required this.amount, required this.orderID});
  final String amount;
  final String orderID;
}

String _requiredString(Map<String, dynamic> json, String key, [String? alias]) {
  final value = json[key] ?? (alias == null ? null : json[alias]);
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing or invalid $key');
  }
  return value.trim();
}

String _optionalString(Map<String, dynamic> json, String key, [String? alias]) {
  final value = json[key] ?? (alias == null ? null : json[alias]);
  if (value == null) return '';
  if (value is! String) throw FormatException('Invalid $key');
  return value.trim();
}

int? _integer(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  throw const FormatException('Invalid fund integer');
}

DateTime? _date(dynamic value) {
  if (value == null || value == '' || value == 0 || value == '0') return null;
  final integer =
      value is int ? value : (value is String ? int.tryParse(value) : null);
  if (integer != null) {
    return DateTime.fromMillisecondsSinceEpoch(
      integer.abs() < 1000000000000 ? integer * 1000 : integer,
      isUtc: true,
    );
  }
  if (value is String) return DateTime.tryParse(value);
  return null;
}
