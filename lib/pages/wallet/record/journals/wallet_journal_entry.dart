/// One posted ledger event, retaining server decimals and event identity.
/// An order may have several events; [id], rather than [orderID], identifies it.
class WalletJournalEntry {
  const WalletJournalEntry({
    required this.id,
    required this.currency,
    required this.bizType,
    required this.type,
    required this.title,
    required this.direction,
    required this.amount,
    required this.availableDelta,
    required this.frozenDelta,
    required this.assetDelta,
    required this.beforeAvailable,
    required this.afterAvailable,
    required this.createdAt,
    required this.bizID,
    required this.orderID,
    required this.counterpartyID,
    required this.groupID,
    required this.remark,
    required this.reason,
    required this.orderStatus,
    required this.chainTxID,
    this.fromAddress = '',
    this.toAddress = '',
  });

  final String id;
  final String currency;
  final String bizType;
  final String type;
  final String title;
  final String direction;
  final String amount;
  final String availableDelta;
  final String frozenDelta;
  final String assetDelta;
  final String? beforeAvailable;
  final String? afterAvailable;
  final int createdAt;
  final String bizID;
  final String orderID;
  final String counterpartyID;
  final String groupID;
  final String remark;
  final String reason;

  /// Current associated order state, never the historical event's state.
  final String orderStatus;
  final String chainTxID;
  final String fromAddress;
  final String toAddress;

  int get decimalScale => _scale(currency);
  BigInt get amountUnits => _units(amount, decimalScale, signed: false);
  BigInt get availableDeltaUnits => _units(availableDelta, decimalScale);
  BigInt get frozenDeltaUnits => _units(frozenDelta, decimalScale);
  BigInt get assetDeltaUnits => _units(assetDelta, decimalScale);

  factory WalletJournalEntry.fromJson(Map<String, dynamic> json) {
    String text(String field, {bool nonempty = false}) {
      final value = json[field];
      if (value is! String || (nonempty && value.trim().isEmpty)) {
        throw FormatException('Invalid journal $field');
      }
      return value;
    }

    // Older journal responses did not include chain addresses.
    String address(String field) => json.containsKey(field) ? text(field) : '';

    final currency = text('currency', nonempty: true);
    final scale = _scale(currency);
    final amount = text('amount');
    final amountUnits = _units(amount, scale, signed: false);
    final available = text('availableDelta');
    final frozen = text('frozenDelta');
    final asset = text('assetDelta');
    final availableUnits = _units(available, scale);
    final frozenUnits = _units(frozen, scale);
    final assetUnits = _units(asset, scale);
    if (availableUnits + frozenUnits != assetUnits) {
      throw const FormatException('Inconsistent journal asset delta');
    }
    final direction = text('direction');
    final expectedDirection = assetUnits > BigInt.zero
        ? 'income'
        : assetUnits < BigInt.zero
            ? 'expense'
            : availableUnits < BigInt.zero
                ? 'freeze'
                : availableUnits > BigInt.zero
                    ? 'unfreeze'
                    : 'neutral';
    if (direction != expectedDirection ||
        (direction != 'neutral' && amountUnits == BigInt.zero)) {
      throw const FormatException('Inconsistent journal direction or amount');
    }
    String? balance(String field) {
      final value = json[field];
      if (value == null) return null;
      if (value is! String) throw FormatException('Invalid journal $field');
      _units(value, scale);
      return value;
    }

    final createdAt = json['createdAt'];
    if (createdAt is! int) {
      throw const FormatException('Invalid journal timestamp');
    }
    return WalletJournalEntry(
      id: text('id', nonempty: true),
      currency: currency,
      bizType: text('bizType', nonempty: true),
      type: text('type', nonempty: true),
      title: text('title', nonempty: true),
      direction: direction,
      amount: amount,
      availableDelta: available,
      frozenDelta: frozen,
      assetDelta: asset,
      beforeAvailable: balance('beforeAvailable'),
      afterAvailable: balance('afterAvailable'),
      createdAt: createdAt,
      bizID: text('bizID'),
      orderID: text('orderID'),
      counterpartyID: text('counterpartyID'),
      groupID: text('groupID'),
      remark: text('remark'),
      reason: text('reason'),
      orderStatus: text('orderStatus'),
      chainTxID: text('chainTxID'),
      fromAddress: address('fromAddress'),
      toAddress: address('toAddress'),
    );
  }

  static int _scale(String currency) => switch (currency) {
        'USDT' || 'TRX' => 6,
        'BI99' => 2,
        _ => throw const FormatException('Invalid journal currency'),
      };

  static BigInt _units(String decimal, int scale, {bool signed = true}) {
    final pattern = signed
        ? RegExp(r'^(-?)(\d+)(?:\.(\d+))?$')
        : RegExp(r'^()(\d+)(?:\.(\d+))?$');
    final match = pattern.firstMatch(decimal);
    final fraction = match?.group(3) ?? '';
    if (match == null || fraction.length > scale) {
      throw const FormatException('Invalid journal decimal');
    }
    final units = BigInt.parse(match.group(2)!) * BigInt.from(10).pow(scale) +
        BigInt.parse(fraction.padRight(scale, '0'));
    return match.group(1) == '-' ? -units : units;
  }
}
