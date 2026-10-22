import 'package:flutter/material.dart';

class BingoDraw {
  const BingoDraw(
      {required this.issue,
      required this.drawTime,
      required this.closeTime,
      required this.special,
      required this.regular,
      this.nextIssue = '',
      this.sumBigSmall = '—',
      this.sumOddEven = '—',
      this.serverTime});

  /// Published numbers belong exclusively to preDrawIssue / preDrawTime.
  final String issue;
  final DateTime drawTime;

  /// Planned next draw time, not a betting cutoff time.
  final DateTime closeTime;
  final String nextIssue;
  final DateTime? serverTime;
  final BingoBall special;
  final List<BingoBall> regular;
  final String sumBigSmall, sumOddEven;

  factory BingoDraw.fromResponse(Map<String, dynamic> response) {
    if ('${response['code']}' != '0' || response['data'] is! Map) {
      throw const FormatException('宾果开奖接口返回异常');
    }
    final data = Map<String, dynamic>.from(response['data'] as Map);
    if ('${data['lotCode']}' != '10214') {
      throw const FormatException('宾果彩种不匹配');
    }
    final issue = '${data['preDrawIssue'] ?? ''}';
    final nextIssue = '${data['drawIssue'] ?? ''}';
    if (issue.isEmpty || nextIssue.isEmpty) {
      throw const FormatException('宾果开奖期号缺失');
    }
    // Never fall back to drawCode: it may represent a different live round.
    final values = '${data['preDrawCode'] ?? ''}'
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .toList();
    if (values.length != 7 ||
        values.any((n) => n == null || n < 1 || n > 49) ||
        values.toSet().length != 7) {
      throw const FormatException('宾果开奖号码不完整');
    }
    final result = data['result'] is Map ? data['result'] as Map : const {};
    final resultNumbers = '${result['nums'] ?? ''}'
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .toList();
    final attributesMatch = resultNumbers.length == 7 &&
        List.generate(7, (i) => values[i] == resultNumbers[i]).every((v) => v);
    BingoBall ball(int index) {
      final position = index + 1;
      return BingoBall(
          values[index]!,
          attributesMatch ? bingoZodiac(result['zodiac$position']) : '—',
          attributesMatch
              ? bingoColor(result['ballColor$position'])
              : Colors.grey,
          bigSmall: attributesMatch
              ? bingoBigSmall(result['bigSmall$position'])
              : '—',
          fiveElement: attributesMatch
              ? bingoFiveElement(result['fiveElement$position'])
              : '—',
          tailSize: attributesMatch
              ? bingoCode(result['bigSmallMantissa$position'], '尾大', '尾小')
              : '—',
          compositeSize: attributesMatch
              ? bingoCode(result['bigSmallComposite$position'], '合大', '合小')
              : '—',
          compositeParity: attributesMatch
              ? bingoCode(result['oddEvenComposite$position'], '合单', '合双')
              : '—',
          oddEven:
              attributesMatch ? bingoOddEven(result['oddEven$position']) : '—');
    }

    return BingoDraw(
      issue: issue,
      nextIssue: nextIssue,
      drawTime: parseBingoTime(data['preDrawTime']),
      closeTime: parseBingoTime(data['drawTime']),
      serverTime: parseBingoTime(data['serverTime'] ?? data['serviceTime']),
      special: ball(6),
      regular: List.unmodifiable(List.generate(6, ball)),
      sumBigSmall:
          attributesMatch ? bingoCode(result['sumBigSmall'], '大', '小') : '—',
      sumOddEven:
          attributesMatch ? bingoCode(result['sumOddEven'], '单', '双') : '—',
    );
  }
}

class BingoBall {
  const BingoBall(this.number, this.zodiac, this.color,
      {this.bigSmall = '—',
      this.fiveElement = '—',
      this.oddEven = '—',
      this.tailSize = '—',
      this.compositeSize = '—',
      this.compositeParity = '—'});
  final int number;
  final String zodiac;
  final Color color;
  final String bigSmall;
  final String fiveElement;
  final String oddEven;
  final String tailSize, compositeSize, compositeParity;
}

String bingoCode(dynamic code, String one, String two) => switch ('$code') {
      '1' => one,
      '2' => two,
      _ => '—',
    };

String bingoBigSmall(dynamic code) => switch ('$code') {
      '0' => '平',
      '1' => '大',
      '2' => '小',
      _ => '—',
    };

String bingoOddEven(dynamic code) => switch ('$code') {
      '0' => '平',
      '1' => '单',
      '2' => '双',
      _ => '—',
    };

String bingoFiveElement(dynamic code) =>
    const {
      '1': '金',
      '2': '木',
      '3': '水',
      '4': '火',
      '5': '土',
    }['$code'] ??
    '—';

// Verified against kai365.cc's own sixWaveColors and zodiac formatter.
Color bingoColor(dynamic code) => switch ('$code') {
      '1' => Colors.red,
      '2' => Colors.green,
      '3' => Colors.blue,
      _ => Colors.grey,
    };
String bingoZodiac(dynamic code) =>
    const {
      '1': '猪',
      '2': '狗',
      '3': '鸡',
      '4': '猴',
      '5': '羊',
      '6': '马',
      '7': '蛇',
      '8': '龙',
      '9': '兔',
      '10': '虎',
      '11': '牛',
      '12': '鼠',
    }['$code'] ??
    '—';

DateTime parseBingoTime(dynamic value) {
  final text = '$value';
  if (!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(text)) {
    throw const FormatException('宾果开奖时间格式错误');
  }
  // The feed supplies Taiwan wall time without an offset.
  final parsed = DateTime.parse('${text.replaceFirst(' ', 'T')}+08:00').toUtc();
  if (formatBingoTime(parsed) != text) {
    throw const FormatException('宾果开奖时间无效');
  }
  return parsed;
}

String formatBingoTime(DateTime value) {
  final t = value.toUtc().add(const Duration(hours: 8));
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${pad(t.month)}-${pad(t.day)} ${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}';
}

String bingoCountdown(BingoDraw? draw, DateTime? now) {
  if (draw == null || now == null) return '开奖 —';
  final seconds = draw.closeTime.difference(now).inSeconds;
  if (seconds <= 0) return '等待开奖';
  return '开奖 ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
