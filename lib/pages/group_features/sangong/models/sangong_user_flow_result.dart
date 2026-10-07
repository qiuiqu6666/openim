import 'sangong_admin_models.dart';

/// Entries and totals share the same business date or selected session.
class SangongUserFlowResult {
  const SangongUserFlowResult({
    this.report = const SangongUserFlowReport(),
    this.returnedLedgerCount = 0,
    this.totalEntries = 0,
    this.nextBeforeId = 0,
    this.coBankHasMore = false,
    this.summary = const {},
    this.detail = const {},
  });

  static const ledgerLimit = 500;
  final SangongUserFlowReport report;
  final int returnedLedgerCount, totalEntries, nextBeforeId;
  final bool coBankHasMore;
  final Map<String, dynamic> summary, detail;
  bool get reachedLedgerLimit => nextBeforeId > 0;

  String coverageMessage({required bool batch}) {
    final scope = batch ? '本批次' : '所选经营日（按上海时间开机日归属）';
    return '$scope共 $totalEntries 条账变，已显示 $returnedLedgerCount 条。'
        '${nextBeforeId > 0 ? '仅展示最近 $ledgerLimit 条，完整金额以汇总为准。' : '所选范围的账变已全部读取。'}'
        '${batch && coBankHasMore ? '合庄出资仅展示最近 500 局。' : ''}';
  }

  factory SangongUserFlowResult.fromJson(Map<String, dynamic> json) {
    final entries = json['entries'];
    final total = json['totalEntries'], next = json['nextBeforeId'];
    if (entries is! List ||
        total is! int ||
        next is! int ||
        total < entries.length ||
        next < 0 ||
        json['summary'] is! Map ||
        json['user'] is! Map) {
      throw const FormatException('用户报表内容不完整');
    }
    return SangongUserFlowResult(
      report: SangongUserFlowReport.fromJson(json),
      returnedLedgerCount: entries.length,
      totalEntries: total,
      nextBeforeId: next,
      coBankHasMore: json['coBankHasMore'] == true,
      summary: Map<String, dynamic>.from(json['summary']),
      detail: {'user': json['user'], 'parent': json['parent']},
    );
  }
}
