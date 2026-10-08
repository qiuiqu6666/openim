import '../../identity/widgets/sangong_identity_view.dart';
import 'package:flutter/material.dart';
import '../../models/sangong_account_flow_entry.dart';
import '../../rebate/widgets/sangong_rebate_receipt_details.dart';
import '../data/report_query_controller.dart';

String reportValue(Object? value) {
  if (value == null) return '—';
  if (value is! num) return '$value';
  final parts = '$value'.split('.');
  final integer = parts.first
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  return parts.length == 1 ? integer : '$integer.${parts.last}';
}

String reportSigned(Object? value) =>
    value is num && value > 0 ? '+${reportValue(value)}' : reportValue(value);
String reportDoorBets(Object? raw) {
  if (raw is! Map || raw.isEmpty) return '暂无各门下注';
  final entries = raw.entries.toList()
    ..sort((a, b) => (int.tryParse('${a.key}') ?? 0)
        .compareTo(int.tryParse('${b.key}') ?? 0));
  return entries.map((e) => '${e.key}门 ${reportValue(e.value)}').join(' · ');
}

String reportTime(Object? raw) {
  if (raw == null || '$raw'.isEmpty) return '—';
  final date = DateTime.tryParse('$raw');
  if (date == null) return '$raw';
  final local = date.toUtc().add(const Duration(hours: 8));
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
}

String reportUser(Map<String, dynamic> row) {
  for (final key in ['nickname']) {
    final value = row[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      return sangongDisplayName(value, '${row['imUserId'] ?? ''}');
    }
  }
  return '用户';
}

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
      'stopped': '已关机',
      'closed': '已结束',
    }['$status'] ??
    reportValue(status);
String ledgerLabel(Object? type) =>
    ledgerKinds[type] ?? SangongAccountFlowEntry.fromJson({'type': type}).label;
const ledgerKinds = {
  '': '全部账变',
  'admin_credit': '上分',
  'admin_debit': '下分',
  'bet_hold': '下注扣分',
  'bet_cancel': '撤注 / 未纳入退款',
  'bet_void': '作废退款',
  'settle_win': '闲家结算',
  'settle_banker': '庄家结算',
  'settle_void': '结算冲正',
  'bet_recall': '撤回下注',
  'bet_restart': '重开退还',
  'rebate_player': '用户返水入账',
  'rebate_agent_diff': '代理返水入账',
  'rebate_player_void': '返水冲正追回',
  'user_transfer_in': '下级划入',
  'user_transfer_out': '向下级划出',
};

class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: child,
      );
}

class ReportMetrics extends StatelessWidget {
  const ReportMetrics(this.values, {super.key, this.hints = const {}});
  final Map<String, Object?> values;
  final Map<String, String> hints;
  @override
  Widget build(BuildContext context) => ReportCard(
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              if (hints[entry.key] != null) ...[
                                const SizedBox(height: 4),
                                Text(hints[entry.key]!,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ],
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
                  ? '暂无记录，请尝试其他批次或筛选条件'
                  : '已显示 ${controller.rows.length} 条${controller.cursor == 0 ? ' · 已全部加载' : ''}')),
      ]);
}

class ReportLedgerTile extends StatelessWidget {
  const ReportLedgerTile(this.row, {super.key});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) {
    final entry = SangongAccountFlowEntry.fromJson(row);
    final amount = row['amount'];
    final negative = amount is num && amount < 0;
    final colors = Theme.of(context).colorScheme;
    return ReportCard(
        child: ExpansionTile(
      leading: SangongIMAvatar(
          userID: '${row['imUserId'] ?? ''}', nickname: reportUser(row)),
      title:
          Text(reportUser(row), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ledgerLabel(row['type'])),
        const SizedBox(height: 4),
        Text(reportTime(row['createdAt']),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        if (entry.isRebate && entry.type != 'rebate_player_void')
          SangongRebateReceiptDetails(
              receipt: entry.rebate, amount: entry.amount),
        Wrap(spacing: 12, runSpacing: 4, children: [
          Text(
              '${negative ? '减少' : amount is num && amount > 0 ? '增加' : '变动'} ${reportSigned(amount)}',
              style: TextStyle(
                  color: negative ? colors.error : colors.primary,
                  fontWeight: FontWeight.w600)),
          Text('变动后积分 ${reportValue(row['balanceAfter'])}'),
        ]),
      ]),
      children: [
        const Divider(height: 1),
        Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SangongPublicAccount(userID: '${row['imUserId'] ?? ''}'),
              SangongPublicAccount(
                  userID: '${row['operator'] ?? ''}', prefix: '操作人账号：'),
            ])),
        ListTile(
            title: Text((row['note']?.toString().isNotEmpty ?? false)
                ? '${row['note']}'
                : '无备注'),
            subtitle: SelectableText(
                '流水编号 ${row['id'] ?? row['ledgerId']}\n批次编号 ${row['sessionId'] ?? '—'}\n关联记录 ${row['refType'] ?? '—'} #${row['refId'] ?? '—'}')),
      ],
    ));
  }
}
