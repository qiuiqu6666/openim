import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import '../models/compensation_detail.dart';
import '../state/compensation_controller.dart';
import 'compensation_tokens.dart';
import 'compensation_countdown.dart';
import 'compensation_hero.dart';
import 'compensation_artwork.dart';

class CompensationContent extends StatelessWidget {
  const CompensationContent(
      {super.key, required this.controller, required this.rulesKey});
  final CompensationController controller;
  final GlobalKey rulesKey;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CompensationHero(detail: controller.detail!, state: controller.state),
      const SizedBox(height: CompensationTokens.space),
      _PoolSummary(detail: controller.detail!),
      const SizedBox(height: CompensationTokens.gap),
      CompensationCountdown(
          remaining: controller.remaining, expired: controller.expired),
      const SizedBox(height: CompensationTokens.space),
      Material(
          key: rulesKey,
          color: CompensationTokens.panel(context),
          shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(CompensationTokens.cardRadius),
              side: BorderSide(
                  color: CompensationTokens.gold.withValues(alpha: .5))),
          clipBehavior: Clip.antiAlias,
          child: Padding(
              padding: const EdgeInsets.all(CompensationTokens.space),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Icon(Icons.description_rounded,
                          color: CompensationTokens.accent(context)),
                      const SizedBox(width: CompensationTokens.gap),
                      Expanded(
                          child: Text(AppCopy.text('活动说明'),
                              style: TextStyle(
                                  color: CompensationTokens.ink(context),
                                  fontWeight: FontWeight.w800,
                                  fontSize: CompensationTokens.body))),
                    ]),
                    const SizedBox(height: CompensationTokens.gap),
                    Text(controller.detail!.description,
                        style: TextStyle(
                            color: cs.onSurfaceVariant,
                            height: 1.6,
                            fontSize: CompensationTokens.body)),
                  ]))),
    ]);
  }
}

class CompensationRules extends StatelessWidget {
  const CompensationRules({super.key, required this.detail});
  final CompensationDetail detail;
  @override
  Widget build(BuildContext context) {
    final rows = [
      (AppCopy.text('活动说明'), detail.description),
      (AppCopy.text('参与条件'), AppCopy.text('本次活动邀请名单内的老用户，每人限领一次。')),
      (
        AppCopy.text('金额规则'),
        detail.minimum == detail.maximum
            ? AppCopy.format('固定金额，每份 {#0} 99币。', [detail.minimum])
            : AppCopy.format(
                '拼手气随机金额，每份 {#0}–{#1} 99币。', [detail.minimum, detail.maximum])
      ),
      (AppCopy.text('到账说明'), AppCopy.text('领取成功后进入99币钱包余额。')),
      (AppCopy.text('到期说明'), AppCopy.text('未领取份额自动退回平台资金池。'))
    ];
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(CompensationTokens.inset),
      decoration: BoxDecoration(
          color: CompensationTokens.panel(context),
          borderRadius: BorderRadius.circular(CompensationTokens.cardRadius),
          border:
              Border.all(color: CompensationTokens.gold.withValues(alpha: .5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: CompensationTokens.gap),
                child: Divider()),
          Semantics(
              header: true,
              child: Text(rows[i].$1,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: CompensationTokens.body))),
          const SizedBox(height: CompensationTokens.gap),
          Text(rows[i].$2,
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  height: 1.6,
                  fontSize: CompensationTokens.body)),
        ]
      ]),
    );
  }
}

class _PoolSummary extends StatelessWidget {
  const _PoolSummary({required this.detail});
  final CompensationDetail detail;
  @override
  Widget build(BuildContext context) {
    Widget item(String title, String value) => Column(children: [
          Text(title,
              style: TextStyle(
                  color: CompensationTokens.ink(context),
                  fontSize: CompensationTokens.body,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: CompensationTokens.gap),
          Text.rich(
              TextSpan(children: [
                TextSpan(text: value.replaceAll('99币', '').trim()),
                if (value.contains('99币'))
                  TextSpan(
                      text: AppCopy.text(' 99币'),
                      style: TextStyle(fontSize: CompensationTokens.label)),
              ]),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: CompensationTokens.accent(context),
                  fontSize: CompensationTokens.posterTitle,
                  fontWeight: FontWeight.w900)),
        ]);
    if (Theme.of(context).brightness == Brightness.light &&
        MediaQuery.textScalerOf(context).scale(CompensationTokens.body) <=
            CompensationTokens.body * 1.3) {
      return LayoutBuilder(
          builder: (context, box) => Stack(children: [
                const CompensationArtwork.states(CompensationArtwork.statePool),
                Positioned(
                    left: box.maxWidth * .19,
                    top: box.maxWidth * .025,
                    width: box.maxWidth * .27,
                    height: box.maxWidth * .105,
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: item(AppCopy.text('总资金池'), detail.poolLabel))),
                Positioned(
                    left: box.maxWidth * .70,
                    top: box.maxWidth * .025,
                    width: box.maxWidth * .25,
                    height: box.maxWidth * .105,
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: item(AppCopy.text('剩余资金'),
                            detail.remainingLabel ?? AppCopy.text('暂未提供')))),
              ]));
    }
    final total = item(AppCopy.text('总资金池'), detail.poolLabel);
    final remaining = item(
        AppCopy.text('剩余资金'), detail.remainingLabel ?? AppCopy.text('暂未提供'));
    return Container(
        padding: const EdgeInsets.all(CompensationTokens.space),
        decoration: BoxDecoration(
            color: CompensationTokens.panel(context),
            border: Border.all(color: CompensationTokens.gold),
            borderRadius: BorderRadius.circular(CompensationTokens.cardRadius)),
        child: LayoutBuilder(builder: (context, constraints) {
          if (MediaQuery.textScalerOf(context).scale(CompensationTokens.body) >
              CompensationTokens.body * 1.3) {
            return Column(children: [total, const Divider(), remaining]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: total),
            const SizedBox(width: CompensationTokens.space),
            Expanded(child: remaining)
          ]);
        }));
  }
}
