import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../res/strings.dart';

/// 99chat's rolling-week message label, using OpenIM millisecond timestamps.
/// [now] is injectable for boundary tests; production uses the local clock.
String formatChatMessageTime(BuildContext context, int timestamp,
    {DateTime? now}) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final current = (now ?? DateTime.now()).toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final clock = DateFormat('HH:mm').format(time);
  if (time.year != today.year) {
    return '${DateFormat('yyyy-MM-dd').format(time)} $clock';
  }
  if (time.isBefore(today.subtract(const Duration(days: 6)))) {
    return '${DateFormat('MM-dd').format(time)} $clock';
  }
  if (time.isBefore(today.subtract(const Duration(days: 1)))) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final weekday = zh
        ? [
            StrRes.monday,
            StrRes.tuesday,
            StrRes.wednesday,
            StrRes.thursday,
            StrRes.friday,
            StrRes.saturday,
            StrRes.sunday
          ][time.weekday - 1]
        : DateFormat('EEEE').format(time);
    return '$weekday $clock';
  }
  if (time.day != today.day) {
    final yesterday = Localizations.localeOf(context).languageCode == 'zh'
        ? '昨天'
        : 'Yesterday';
    return '$yesterday $clock';
  }
  return clock;
}
