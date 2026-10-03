import 'package:intl/intl.dart';

/// Parses wallet/API datetime values into device local [DateTime].
///
/// Backend red-packet timestamps are Java [Instant] serialized as UTC ISO8601
/// strings ending with `Z`, sometimes with nanosecond fractional digits.
DateTime? parseWalletApiTimeToLocal(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toLocal();
  if (raw is int) {
    return _epochMillisToLocal(raw);
  }
  if (raw is num) {
    return _epochMillisToLocal(raw.toInt());
  }

  final text = raw.toString().trim();
  if (text.isEmpty || text == 'null') return null;

  if (RegExp(r'^\d{10,13}$').hasMatch(text)) {
    final parsed = _epochMillisToLocal(int.parse(text));
    if (parsed != null) return parsed;
  }

  final normalized = _normalizeInstantString(text);
  final parsed = DateTime.tryParse(normalized);
  if (parsed != null) {
    if (parsed.isUtc || _hasExplicitTimezone(normalized)) {
      return parsed.toLocal();
    }
    // Wallet Instant strings without suffix are still UTC wall-clock.
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    ).toLocal();
  }
  try {
    final wall = DateFormat('yyyy-MM-dd HH:mm:ss').parseStrict(text);
    // Same Instant convention as suffix-less ISO: treat wall clock as UTC.
    return DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
      wall.millisecond,
      wall.microsecond,
    ).toLocal();
  } catch (_) {
    return null;
  }
}

/// Reads claim timestamp fields from a red-packet claim map.
DateTime? parseWalletApiClaimTime(Map<String, dynamic> map) {
  final nested = map['claim'];
  if (nested is Map) {
    final nestedMap = Map<String, dynamic>.from(nested);
    final parsed = _parseFirstClaimTimeField(nestedMap);
    if (parsed != null) return parsed;
  }

  return _parseFirstClaimTimeField(map);
}

DateTime? _parseFirstClaimTimeField(Map<String, dynamic> map) {
  for (final key in const [
    'claimedAt',
    'claimed_at',
    'claimTime',
    'claim_time',
    'claimAt',
    'claim_at',
    'creditedAt',
    'credited_at',
    'createTime',
    'create_time',
    'createdAt',
    'created_at',
    'time',
    'timestamp',
  ]) {
    final parsed = parseWalletApiTimeToLocal(map[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

String formatWalletApiDateTime(
  dynamic raw, {
  String pattern = 'yyyy-MM-dd HH:mm',
}) {
  final parsed = _coerceLocalTime(raw);
  if (parsed == null) {
    final text = raw?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? '--' : text;
  }
  return DateFormat(pattern).format(parsed);
}

/// Claim list time: today shows clock, older rows include month/day.
String formatWalletApiClaimListTime(dynamic raw) {
  final parsed = _coerceLocalTime(raw);
  if (parsed == null) return '--:--:--';

  final now = DateTime.now();
  final sameDay = parsed.year == now.year &&
      parsed.month == now.month &&
      parsed.day == now.day;
  if (sameDay) {
    return DateFormat('HH:mm:ss').format(parsed);
  }
  return DateFormat('MM-dd HH:mm:ss').format(parsed);
}

String formatWalletApiClock(dynamic raw) {
  final parsed = _coerceLocalTime(raw);
  if (parsed == null) return '--:--:--';
  return DateFormat('HH:mm:ss').format(parsed);
}

DateTime? _coerceLocalTime(dynamic raw) {
  if (raw is DateTime) return raw.toLocal();
  return parseWalletApiTimeToLocal(raw);
}

DateTime? _epochMillisToLocal(int raw) {
  if (raw <= 0) return null;
  final ms = raw < 1000000000000 ? raw * 1000 : raw;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
}

bool _hasExplicitTimezone(String text) {
  return text.endsWith('Z') ||
      RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(text);
}

String _normalizeInstantString(String text) {
  var value = text.replaceFirst(' ', 'T');

  // Java Instant may serialize 4-9 fractional digits; Dart accepts up to 6.
  final fractional = RegExp(
    r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.(\d+)(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(value);
  if (fractional != null) {
    final digits = fractional.group(2)!;
    final suffix = fractional.group(3)!;
    final micros = digits.padRight(6, '0').substring(0, 6);
    value = '${fractional.group(1)}.$micros$suffix';
  }

  return value;
}
