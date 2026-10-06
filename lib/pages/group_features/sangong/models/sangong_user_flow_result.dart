import 'sangong_admin_models.dart';

/// The current user-flow contract returns at most 500 newest ledger rows.
/// It has no date filter or continuation token; counts are not totals.
class SangongUserFlowResult {
  const SangongUserFlowResult({
    this.report = const SangongUserFlowReport(),
    this.returnedLedgerCount = 0,
  });

  static const ledgerLimit = 500;
  final SangongUserFlowReport report;
  final int returnedLedgerCount;
  bool get reachedLedgerLimit => returnedLedgerCount >= ledgerLimit;

  String coverageMessage({required bool batch}) {
    final scope = batch ? '本批次' : '所选日期';
    final source = batch ? '本批次最近账变' : '全部历史最近账变';
    final limit =
        reachedLedgerLimit ? '已达到 $ledgerLimit 条上限，较早明细可能缺失。' : '较早明细可能缺失。';
    return '$scope明细来自$source（已读取 $returnedLedgerCount 条，最多 $ledgerLimit 条）。'
        '$limit完整金额以汇总为准。'
        '${batch ? '' : '按开机批次查询可缩小范围；没有明细不表示当天没有交易。'}';
  }

  factory SangongUserFlowResult.fromJson(Map<String, dynamic> json) {
    final raw = json['flow'];
    final flow = raw is Map ? Map<String, dynamic>.from(raw) : json;
    // entries and ledgerFlow can be aliases of the same all-ledger result.
    // Count raw rows before UI type/date filtering, including rebates.
    final entries = flow['entries'];
    final ledger = flow['ledgerFlow'] ??
        flow['ledger_flow'] ??
        flow['balanceChanges'] ??
        flow['balance_changes'];
    final count = entries is List
        ? entries.length
        : ledger is List
            ? ledger.length
            : 0;
    return SangongUserFlowResult(
      report: SangongUserFlowReport.fromJson(json),
      returnedLedgerCount: count,
    );
  }
}
