/// Legacy draw reports use separator lines which resemble Setext headings.
/// Recognize the complete report structure, not arbitrary separators in chat.
bool isChatDrawReportText(String text) {
  final lines = text.split(RegExp(r'\r?\n'));
  if (lines.length < 7) return false;
  final first = lines.first.trim();
  if (!RegExp(r'^[\[【]第\d+期[\]】]$').hasMatch(first)) return false;
  return lines.any((line) => RegExp(r'^={3,}$').hasMatch(line.trim())) &&
      lines.any((line) => line.trim() == '--开奖号码为--') &&
      lines.any((line) => RegExp(r'^开\s*[:：]\s*[（(]').hasMatch(line.trim())) &&
      lines.any((line) => RegExp(r'^倍\s*[（(]').hasMatch(line.trim())) &&
      lines.any((line) => line.trim().startsWith('结算如下'));
}
