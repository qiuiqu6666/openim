// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
/// 开彩录入：仅允许 00～99 的两位整数（无小数）。
class SangongDrawInputFormat {
  SangongDrawInputFormat._();

  static final RegExp _digitsOnly = RegExp(r'^\d{1,2}$');

  /// 从服务端/历史值还原可编辑文本；不符合 00～99 则置空。
  static String sanitizeInitial(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || !_digitsOnly.hasMatch(trimmed)) {
      return '';
    }
    final value = int.tryParse(trimmed);
    if (value == null || value < 0 || value > 99) {
      return '';
    }
    return trimmed;
  }

  /// 追加一位数字；已满 2 位则忽略。
  static String appendDigit(String current, String digit) {
    if (digit.length != 1 ||
        digit.codeUnitAt(0) < 48 ||
        digit.codeUnitAt(0) > 57) {
      return current;
    }
    if (current.length >= 2) {
      return current;
    }
    return '$current$digit';
  }

  /// 删除末位。
  static String deleteLast(String current) {
    if (current.isEmpty) {
      return current;
    }
    return current.substring(0, current.length - 1);
  }

  /// 是否可提交（0～99，含 00）。
  static bool isValidEntry(String raw) {
    final trimmed = raw.trim();
    if (!_digitsOnly.hasMatch(trimmed)) {
      return false;
    }
    final value = int.tryParse(trimmed);
    return value != null && value >= 0 && value <= 99;
  }

  /// 提交给 API 的字符串：统一两位，如 `7` → `07`。
  static String normalizeForSubmit(String raw) {
    final trimmed = raw.trim();
    if (!isValidEntry(trimmed)) {
      return '';
    }
    return int.parse(trimmed).toString().padLeft(2, '0');
  }

  /// 两位开彩数的个位（尾数）。
  static int tailDigit(String normalizedTwoDigit) {
    if (normalizedTwoDigit.length != 2) {
      return 0;
    }
    return int.parse(normalizedTwoDigit.substring(1));
  }

  /// 各门尾数（个位）之和。
  static int sumTailDigits(Iterable<String> normalizedTwoDigitEntries) {
    var sum = 0;
    for (final entry in normalizedTwoDigitEntries) {
      if (entry.length == 2) {
        sum += tailDigit(entry);
      }
    }
    return sum;
  }

  /// 全部尾数相加的个位须为 0（即总和为 0、10、20…）。
  static bool isTailSumValid(Iterable<String> normalizedTwoDigitEntries) {
    final entries = normalizedTwoDigitEntries.toList();
    if (entries.isEmpty || entries.any((e) => e.length != 2)) {
      return false;
    }
    return sumTailDigits(entries) % 10 == 0;
  }

  /// 用于界面提示：尾数合计的个位（0 表示通过）。
  static int tailSumCheckDigit(Iterable<String> normalizedTwoDigitEntries) {
    return sumTailDigits(normalizedTwoDigitEntries) % 10;
  }
}
