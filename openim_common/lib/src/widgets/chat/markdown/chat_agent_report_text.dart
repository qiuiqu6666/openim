/// Legacy agent summaries contain literal rank prefixes and separator lines.
/// Match the report structure so regular Markdown messages stay supported.
bool isChatAgentReportText(String text) {
  final lines =
      text.split(RegExp(r'\r?\n')).map((line) => line.trim()).toList();
  return lines.any(
          (line) => RegExp(r'^#0\s*[:：].*一级数量\s*[:：]\s*\d+').hasMatch(line)) &&
      lines.any((line) => RegExp(r'^={3,}$').hasMatch(line)) &&
      lines.any((line) => RegExp(r'^#\d+\s*总计流水\s*[:：]').hasMatch(line)) &&
      lines.any((line) => RegExp(r'^剩余反[水款]\s*[:：]').hasMatch(line)) &&
      lines.any((line) => RegExp(r'^已经反[水款]\s*[:：]').hasMatch(line));
}
