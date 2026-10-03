class WalletSubmitException implements Exception {
  final bool requestSent;
  final String message;

  WalletSubmitException({
    required this.requestSent,
    required this.message,
  });

  @override
  String toString() => message;
}

enum WalletOrderType {
  transfer,
  redPacket,
  receive,
  swap,
}

enum WalletOrderState {
  idle,
  created,
  confirming,
  password,
  submitting,
  accepted,
  pending,
  unknown,
  success,
  failed,
  expired,
  cancelled,
  refunded,
}

enum WalletOrderErr {
  none,
  invalidReceiver,
  emptyAmount,
  invalidAmount,
  invalidPrecision,
  tooLong,
  insufficientBalance,
  insufficientFee,
  invalidCount,
  countOverLimit,
  groupNotReady,
  networkMismatch,
  passwordWrong,
  passwordLocked,
  networkError,
  duplicateSubmit,
  unknown,
}

class WalletAmount {
  final String coin;
  final int minor;
  final int scale;

  const WalletAmount({
    required this.coin,
    required this.minor,
    required this.scale,
  });

  bool get isPositive => minor > 0;

  String get text => formatMinor(minor, scale);

  static WalletAmount? parse(
    String raw, {
    required String coin,
    required int scale,
    int maxInt = 12,
  }) {
    final s = clean(raw, scale: scale, maxInt: maxInt);
    if (s.isEmpty) return null;

    final parts = s.split('.');
    if (parts.length > 2) return null;

    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final decPart = parts.length == 2 ? parts[1] : '';
    if (intPart.length > maxInt) return null;
    if (decPart.length > scale) return null;

    final joined = intPart + decPart.padRight(scale, '0');
    final minor = int.tryParse(joined);
    if (minor == null) return null;

    return WalletAmount(coin: coin, minor: minor, scale: scale);
  }

  static WalletAmount? parseStrict(
    String raw, {
    required String coin,
    required int scale,
    int maxInt = 12,
  }) {
    final s = raw.trim().replaceAll(',', '');
    if (s.isEmpty) return null;
    if (!RegExp(r'^\d+(\.\d*)?$|^\.\d+$').hasMatch(s)) return null;
    if (s.split('.').length > 2) return null;

    final parts = s.startsWith('.') ? ['0', s.substring(1)] : s.split('.');
    final intPartRaw = parts[0];
    final decPart = parts.length == 2 ? parts[1] : '';
    if (intPartRaw.isEmpty) return null;
    if (intPartRaw.length > 1 && intPartRaw.startsWith('0')) return null;
    if (intPartRaw.length > maxInt) return null;
    if (decPart.length > scale) return null;

    final intPart = intPartRaw;
    final joined = intPart + decPart.padRight(scale, '0');
    final minor = int.tryParse(joined);
    if (minor == null) return null;

    return WalletAmount(coin: coin, minor: minor, scale: scale);
  }

  static String clean(
    String raw, {
    required int scale,
    int maxInt = 12,
  }) {
    var s = raw.trim().replaceAll(',', '').replaceAll(RegExp(r'[^0-9.]'), '');
    if (s.isEmpty) return '';

    final firstDot = s.indexOf('.');
    if (firstDot >= 0) {
      final before = s.substring(0, firstDot + 1);
      final after = s.substring(firstDot + 1).replaceAll('.', '');
      s = before + after;
    }

    if (s.startsWith('.')) s = '0$s';

    final parts = s.split('.');
    var intPart = parts[0].replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (intPart.isEmpty) intPart = '0';
    if (intPart.length > maxInt) intPart = intPart.substring(0, maxInt);

    if (parts.length == 1) return intPart;

    var decPart = parts[1];
    if (decPart.length > scale) decPart = decPart.substring(0, scale);
    return '$intPart.$decPart';
  }

  static String formatMinor(int minor, int scale) {
    final negative = minor < 0;
    var s = minor.abs().toString().padLeft(scale + 1, '0');
    final intPart = s.substring(0, s.length - scale);
    var decPart = scale == 0 ? '' : s.substring(s.length - scale);
    decPart = decPart.replaceFirst(RegExp(r'0+$'), '');
    final v = decPart.isEmpty ? intPart : '$intPart.$decPart';
    return negative ? '-$v' : v;
  }

  /// 展示用格式：至少保留 [minFraction] 位小数（默认 2 位），
  /// 更高精度的有效小数会保留，仅裁掉超出 [minFraction] 之后多余的 0。
  /// 例如 1 -> 1.00，1.5 -> 1.50，1.2345 -> 1.2345。
  static String formatDisplay(int minor, int scale, {int minFraction = 2}) {
    final negative = minor < 0;
    final digits = minor.abs().toString().padLeft(scale + 1, '0');
    final intPart = digits.substring(0, digits.length - scale);
    var decPart = scale == 0 ? '' : digits.substring(digits.length - scale);
    decPart = decPart.replaceFirst(RegExp(r'0+$'), '');
    if (decPart.length < minFraction) {
      decPart = decPart.padRight(minFraction, '0');
    }
    final v = decPart.isEmpty ? intPart : '$intPart.$decPart';
    return negative ? '-$v' : v;
  }

  static String formatFixed(int minor, int scale) {
    final negative = minor < 0;
    final s = minor.abs().toString().padLeft(scale + 1, '0');
    final intPart = s.substring(0, s.length - scale);
    final decPart = scale == 0 ? '' : s.substring(s.length - scale);
    final v = scale == 0 ? intPart : '$intPart.$decPart';
    return negative ? '-$v' : v;
  }
}
