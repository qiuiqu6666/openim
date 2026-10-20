import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import '../models/sangong_rebate_receipt.dart';

class SangongRebateReceiptDetails extends StatelessWidget {
  const SangongRebateReceiptDetails(
      {super.key, required this.receipt, required this.amount});
  final SangongRebateReceipt? receipt;
  final int amount;
  @override
  Widget build(BuildContext context) {
    final data = receipt;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (data != null)
            Text(
                '${AppCopy.text(data.claimLabel)}${data.agent ? AppCopy.text(' · 代理差额返水') : ''}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          Wrap(spacing: 12, runSpacing: 4, children: [
            Text(
                '${data?.turnoverBasis == 'team_total' ? AppCopy.text('团队流水（累计）') : '本次返水流水'}：${data?.turnover ?? AppCopy.text('未记录')}'),
            Text(
                '${data?.agent == true ? '本人返水比例' : '返水比例'}：${data?.rateLabel ?? AppCopy.text('未记录')}'),
            Text(AppCopy.format('返水金额：{#0}', [data?.amount ?? amount])),
          ]),
          if (data == null)
            Text(AppCopy.text('历史记录未保存本次流水和比例，金额以实际账变为准。'),
                style: TextStyle(fontSize: 12, color: muted))
          else if (data.agent)
            Text(AppCopy.text('按各分支比例差额计算，金额不是团队流水乘以本人比例。'),
                style: TextStyle(fontSize: 12, color: muted)),
        ]));
  }
}
