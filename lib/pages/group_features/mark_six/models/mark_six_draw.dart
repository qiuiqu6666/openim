// Adapted from 99chat test_page.dart result model. No demonstration draws.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'mark_six_json.dart';

class MarkSixDraw {
  MarkSixDraw(this.raw) : attributes = markSixMap(raw['attributes']);
  final Map<String, dynamic> raw;
  final Map<String, dynamic> attributes;
  String get issue => '${raw['issueLabel'] ?? raw['issue'] ?? '—'}';
  String get id => '${raw['issue'] ?? ''}';
  String get status => '${raw['status'] ?? ''}';
  bool get drawn => status == 'drawn';
  int? get special => int.tryParse('${attributes['special'] ?? ''}');
  String get number => special?.toString().padLeft(2, '0') ?? '—';
  String value(String key) => '${attributes[key] ?? '—'}';
  String get zodiac => value('zodiac');
  String get wave => value('wave');
  String get time {
    final stamp = raw['drawAt'];
    if (stamp is! num) return '—';
    final china =
        DateTime.fromMillisecondsSinceEpoch(stamp.toInt(), isUtc: true)
            .add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(china.month)}-${two(china.day)} ${two(china.hour)}:${two(china.minute)}';
  }
}
