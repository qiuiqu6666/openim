import 'package:flutter/material.dart';
import '../../models/sangong_account_flow_entry.dart';
import '../data/report_query_controller.dart';

String reportValue(Object? value) => value == null ? '—' : '$value';
String reportTime(Object? raw) {
  if (raw == null || '$raw'.isEmpty) return '—';
  final date = DateTime.tryParse('$raw');
  if (date == null) return '$raw';
  final local = date.toUtc().add(const Duration(hours: 8));
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
}

String reportUser(Map<String, dynamic> row) =>
    '${row['nickname'] ?? row['imUserId'] ?? '用户'}';
String reportPhase(Object? status) =>
    const {
      'await_banker': '待定庄',
      'await_banker_door': '待选庄门',
      'betting': '下注阶段',
      'co_bank_closed': '合庄截止',
      'settled': '已结算',
      'voided': '已作废',
      'running': '运行中',
      'idle': '已关机',
    }['$status'] ??
    reportValue(status);
String ledgerLabel(Object? type) =>
    SangongAccountFlowEntry.fromJson({'type': type}).label;
const ledgerKinds = {
  '': '全部账变',
  'admin_credit': '上分',
  'admin_debit': '下分',
  'bet_hold': '下注扣分',
  'bet_cancel': '撤注 / 未纳入退款',
  'bet_void': '作废退款',
  'settle_win': '闲家结算',
  'settle_banker': '庄家结算',
  'user_transfer_in': '划入',
  'user_transfer_out': '划出',
};

class ReportMetrics extends StatelessWidget {
  const ReportMetrics(this.values, {super.key});
  final Map<String, Object?> values;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(builder: (_, box) {
            final columns = box.maxWidth > 600 ? 4 : 2;
            return Wrap(
                spacing: 12,
                runSpacing: 16,
                children: values.entries
                    .map((entry) => SizedBox(
                        width: (box.maxWidth - 12 * (columns - 1)) / columns,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.key,
                                  style: Theme.of(context).textTheme.bodySmall),
                              Text(reportValue(entry.value),
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ])))
                    .toList());
          })));
}

class ReportPagingFooter extends StatelessWidget {
  const ReportPagingFooter(this.controller, {super.key});
  final ReportQueryController controller;
  @override
  Widget build(BuildContext context) => Column(children: [
        if (controller.error != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(controller.error!)),
        if (controller.busy)
          const Padding(
              padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
        if (!controller.busy && controller.error != null)
          TextButton(
              onPressed: () => controller.load(), child: const Text('刷新重试')),
        if (!controller.busy && controller.cursor > 0)
          TextButton(
              onPressed: () => controller.load(more: true),
              child: const Text('加载更多')),
        if (!controller.busy && controller.error == null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Text(controller.rows.isEmpty
                  ? '暂无记录'
                  : '已显示 ${controller.rows.length} 条${controller.cursor == 0 ? ' · 已全部加载' : ''}')),
      ]);
}

class ReportLedgerTile extends StatelessWidget {
  const ReportLedgerTile(this.row, {super.key});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) => Card(
          child: ExpansionTile(
        title: Text('${reportUser(row)} · ${ledgerLabel(row['type'])}'),
        subtitle: Text(
            '${reportTime(row['createdAt'])}\n变动 ${reportValue(row['amount'])} · 余分 ${reportValue(row['balanceAfter'])}'),
        children: [
          ListTile(
              title: Text('${row['note'] ?? ''}'),
              subtitle: SelectableText(
                  '流水 #${row['id'] ?? row['ledgerId']}\n用户 ${row['imUserId'] ?? row['userId']}\n操作人 ${row['operator'] ?? '—'}\n批次 ${row['sessionId'] ?? '—'} · 关联 ${row['refType'] ?? ''} #${row['refId'] ?? '—'}'))
        ],
      ));
}
