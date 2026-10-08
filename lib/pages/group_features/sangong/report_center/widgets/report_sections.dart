import 'package:flutter/material.dart';
import 'report_widgets.dart';

/// Consistent section hierarchy and plain-language explanations for reports.
class ReportSection extends StatelessWidget {
  const ReportSection(this.title,
      {super.key, this.description, this.icon = Icons.bar_chart_outlined});
  final String title;
  final String? description;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ])),
      ]));
}

class ReportNotice extends StatelessWidget {
  const ReportNotice(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
                child:
                    Text(text, style: Theme.of(context).textTheme.bodySmall)),
          ])));
}

class ReportBalanceCard extends StatelessWidget {
  const ReportBalanceCard(this.balance, {super.key, this.users});
  final Object? balance, users;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(16)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 20, color: colors.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('全群当前积分',
                        style: TextStyle(color: colors.onPrimaryContainer))),
                Text('实时',
                    style: TextStyle(
                        color: colors.onPrimaryContainer, fontSize: 12)),
              ]),
              const SizedBox(height: 10),
              Text(reportValue(balance),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('${reportValue(users)} 位登记用户 · 当前余额合计',
                  style: TextStyle(
                      color: colors.onPrimaryContainer, fontSize: 12)),
            ])));
  }
}
