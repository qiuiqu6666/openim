// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:flutter/material.dart';
import '../rebate/widgets/sangong_rebate_receipt_details.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_account_flow_entry.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_co_bank_flow_entry.dart';

/// Renders ledger events, not synthetic bets with invented settlement status.
class SangongAccountFlowList extends StatelessWidget {
  const SangongAccountFlowList(
      {super.key,
      required this.entries,
      required this.bets,
      this.contributions = const [],
      this.operatorNames = const {}});
  final Map<String, String> operatorNames;
  final List<SangongAccountFlowEntry> entries;
  final List<SangongCoBankFlowEntry> contributions;
  final bool bets;

  String _signed(int value) => value > 0 ? '+$value' : '$value';
  String _time(String raw) {
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return raw.trim().isEmpty ? '时间未提供' : raw.trim();
    final local = parsed.toLocal();
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty && contributions.isEmpty) {
      return const Center(child: Text('暂无记录'));
    }
    final total = entries.fold<int>(0, (sum, e) => sum + e.amount);
    final credit = entries
        .where((e) => e.isCredit)
        .fold<int>(0, (sum, e) => sum + e.amount);
    final debit = entries
        .where((e) => e.isDebit)
        .fold<int>(0, (sum, e) => sum - e.amount);
    final rebate = entries
        .where((e) => e.isRebate)
        .fold<int>(0, (sum, e) => sum + e.amount);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    const labelStyle = TextStyle(color: Color(0xFF88B04B));
    const amountStyle = TextStyle(color: Color(0xFFC0504D));
    final textStyle = TextStyle(
      fontSize: 15,
      height: 1.25,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: entries.length + contributions.length + 1,
      itemBuilder: (_, index) {
        if (index == entries.length + contributions.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '本页${entries.length}笔 ', style: labelStyle),
                    if (contributions.isNotEmpty)
                      TextSpan(
                          text: '出资${contributions.length}笔 ',
                          style: labelStyle),
                    if (bets) ...[
                      const TextSpan(text: '账变合计:', style: labelStyle),
                      TextSpan(text: _signed(total), style: amountStyle),
                    ] else ...[
                      const TextSpan(text: '总上分:', style: labelStyle),
                      TextSpan(text: '$credit', style: amountStyle),
                      const TextSpan(text: ' 总下分:', style: labelStyle),
                      TextSpan(text: '$debit'),
                      const TextSpan(text: ' 返水净入账:', style: labelStyle),
                      TextSpan(text: _signed(rebate), style: amountStyle),
                    ],
                  ]),
                  style: textStyle),
            ),
          );
        }
        if (index >= entries.length) {
          final entry = contributions[index - entries.length];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text:
                          '【第${entry.periodNo}期】 ${entry.isMainBanker ? '主庄限额' : '合庄出资'}:',
                      style: labelStyle),
                  TextSpan(text: '${entry.amount}', style: amountStyle),
                  TextSpan(
                      text: ' 占股:${entry.sharePercent}% 总池:${entry.poolTotal}',
                      style: labelStyle),
                  TextSpan(
                      text:
                          ' 已分摊:${entry.settledAmount > 0 ? '+' : ''}${entry.settledAmount}'),
                  TextSpan(text: '（不扣积分）', style: TextStyle(color: muted)),
                ]),
                style: textStyle),
          );
        }
        final entry = entries[index];
        return Padding(
          key: ValueKey('sangong-ledger-${entry.ledgerId}'),
          padding: const EdgeInsets.symmetric(vertical: 1),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text:
                          '【${_time(entry.createdAt)}】 ${bets && entry.periodNo != null ? '第${entry.periodNo}期 ' : ''}${entry.label}:',
                      style: labelStyle),
                  TextSpan(text: _signed(entry.amount), style: amountStyle),
                  const TextSpan(text: ' 剩余:', style: labelStyle),
                  TextSpan(text: '${entry.balanceAfter}'),
                ]),
                style: textStyle),
            if (entry.isRebate && entry.type != 'rebate_player_void')
              SangongRebateReceiptDetails(
                  receipt: entry.rebate, amount: entry.amount),
            if (!bets)
              Text(
                '操作人：${operatorNames[entry.operator.trim()] == null ? (entry.operator.trim().isEmpty ? '未提供' : entry.operator.trim()) : '${operatorNames[entry.operator.trim()]}（${entry.operator.trim()}）'}',
                style: TextStyle(fontSize: 12, height: 1.2, color: muted),
              ),
            if (entry.note.isNotEmpty && entry.note != entry.label)
              Text(entry.note,
                  style: TextStyle(fontSize: 12, height: 1.2, color: muted)),
          ]),
        );
      },
    );
  }
}
