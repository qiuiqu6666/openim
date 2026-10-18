enum CompensationState { unclaimed, claimed, ended, ineligible }

String moneyText(Object? value) {
  if (value is! String || !RegExp(r'^\d{1,17}\.\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid compensation amount');
  }
  return value;
}

class CompensationDetail {
  CompensationDetail.fromJson(Map<String, dynamic> json)
      : id = _text(json['activity'], 'id'),
        title = _text(json['activity'], 'title'),
        description = _text(json['activity'], 'description'),
        total = moneyText((json['activity'] as Map)['totalAmount']),
        remainingAmount = (json['activity'] as Map)['remainingAmount'] == null
            ? null
            : moneyText((json['activity'] as Map)['remainingAmount']),
        minimum = moneyText((json['activity'] as Map)['minAmount']),
        maximum = moneyText((json['activity'] as Map)['maxAmount']),
        deadline = DateTime.parse(_text(json['activity'], 'deadline')),
        serverTime = DateTime.parse(json['serverTime'] as String),
        activityEnded = _text(json['activity'], 'status') == 'ended',
        state = CompensationState.values.byName(json['state'] as String),
        amount = json['state'] == 'claimed' ? moneyText(json['amount']) : null,
        claimedAt = json['state'] == 'claimed'
            ? DateTime.parse(json['claimedAt'] as String)
            : null,
        receiptID =
            json['state'] == 'claimed' ? _text(json, 'receiptID') : null {
    if (state == CompensationState.claimed &&
        json['arrivalStatus'] != 'credited') {
      throw const FormatException('Unconfirmed compensation receipt');
    }
    if (!{'active', 'ended'}.contains(_text(json['activity'], 'status'))) {
      throw const FormatException('Unpublished compensation activity');
    }
  }
  final String id, title, description, total, minimum, maximum;
  final DateTime deadline, serverTime;
  final bool activityEnded;
  final CompensationState state;
  final String? amount, receiptID, remainingAmount;
  final DateTime? claimedAt;
  String? get remainingLabel {
    final value = remainingAmount;
    if (value == null) return null;
    final cents = BigInt.parse(value.replaceAll('.', ''));
    if (cents >= BigInt.from(1000000) &&
        cents % BigInt.from(10000) == BigInt.zero) {
      final hundredths = cents ~/ BigInt.from(10000);
      final fraction =
          (hundredths % BigInt.from(100)).toString().padLeft(2, '0');
      return '${hundredths ~/ BigInt.from(100)}${fraction == '00' ? '' : '.$fraction'}万99币';
    }
    return '$value 99币';
  }

  String get poolLabel {
    final units = BigInt.parse(total.replaceAll('.', ''));
    final million = BigInt.from(1000000);
    return units % million == BigInt.zero
        ? '${units ~/ million}万99币'
        : '$total 99币';
  }

  static String _text(dynamic json, String key) {
    if (json is! Map || json[key] is! String || (json[key] as String).isEmpty) {
      throw FormatException('Invalid compensation $key');
    }
    return json[key] as String;
  }
}
