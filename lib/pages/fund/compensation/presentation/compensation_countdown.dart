import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'compensation_artwork.dart';
import 'compensation_tokens.dart';

class CompensationCountdown extends StatelessWidget {
  const CompensationCountdown(
      {super.key, required this.remaining, required this.expired});
  final Duration remaining;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final safe = expired || remaining.isNegative ? Duration.zero : remaining;
    final values = [
      safe.inDays,
      safe.inHours % 24,
      safe.inMinutes % 60,
      safe.inSeconds % 60
    ];
    final units = ['天', AppCopy.text('时'), '分', '秒'];
    final cs = Theme.of(context).colorScheme;
    final heading = expired ? AppCopy.text('活动已结束') : AppCopy.text('活动剩余时间');
    final adaptive = Theme.of(context).brightness == Brightness.dark ||
        MediaQuery.textScalerOf(context).scale(CompensationTokens.body) >
            CompensationTokens.body * 1.3 ||
        safe.inDays > 99;
    final accent =
        expired ? cs.onSurfaceVariant : CompensationTokens.accent(context);
    return Container(
      decoration: BoxDecoration(
          color: CompensationTokens.panel(context),
          borderRadius: BorderRadius.circular(CompensationTokens.cardRadius),
          border:
              Border.all(color: CompensationTokens.gold.withValues(alpha: .5))),
      child: Column(children: [
        if (!adaptive)
          Semantics(
              label: AppCopy.format('{#0}，{#1}天{#2}小时{#3}分{#4}秒',
                  [heading, values[0], values[1], values[2], values[3]]),
              excludeSemantics: true,
              child: LayoutBuilder(
                  builder: (context, box) => Stack(children: [
                        const CompensationArtwork(
                            Rect.fromLTWH(1005, 405, 475, 185)),
                        Positioned(
                            top: box.maxWidth * .06,
                            left: box.maxWidth * .39,
                            right: box.maxWidth * .14,
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(heading,
                                    style: TextStyle(
                                        color: CompensationTokens.ink(context),
                                        fontSize: CompensationTokens.space,
                                        fontWeight: FontWeight.w800)))),
                        for (var i = 0; i < 4; i++) ...[
                          Positioned(
                              left: box.maxWidth * (.06 + i * .23),
                              top: box.maxWidth * .197,
                              width: box.maxWidth * .14,
                              height: box.maxWidth * .13,
                              child: Center(
                                  child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                          values[i].toString().padLeft(2, '0'),
                                          style: TextStyle(
                                              color: accent,
                                              fontSize: CompensationTokens
                                                  .posterAmount,
                                              fontWeight: FontWeight.w900))))),
                          Positioned(
                              left: box.maxWidth * (.21 + i * .23),
                              top: box.maxWidth * .232,
                              child: Text(units[i],
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: CompensationTokens.label))),
                        ],
                      ])))
        else
          Padding(
              padding: const EdgeInsets.all(CompensationTokens.space),
              child: Column(children: [
                Row(children: [
                  Icon(Icons.schedule_rounded, color: accent),
                  const SizedBox(width: CompensationTokens.gap),
                  Expanded(
                      child: Text(heading,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: CompensationTokens.ink(context),
                              fontSize: CompensationTokens.space,
                              fontWeight: FontWeight.w800)))
                ]),
                const SizedBox(height: CompensationTokens.space),
                Semantics(
                    label: AppCopy.format('{#0}天{#1}小时{#2}分{#3}秒',
                        [values[0], values[1], values[2], values[3]]),
                    excludeSemantics: true,
                    child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: CompensationTokens.gap,
                        runSpacing: CompensationTokens.gap,
                        children: [
                          for (var i = 0; i < 4; i++)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                  padding: const EdgeInsets.all(
                                      CompensationTokens.gap),
                                  decoration: BoxDecoration(
                                      color: CompensationTokens.tint(context),
                                      borderRadius: BorderRadius.circular(
                                          CompensationTokens.radius)),
                                  child: Text(
                                      values[i].toString().padLeft(2, '0'),
                                      style: TextStyle(
                                          color: accent,
                                          fontSize:
                                              CompensationTokens.posterAmount,
                                          fontWeight: FontWeight.w900))),
                              const SizedBox(width: CompensationTokens.small),
                              Text(units[i]),
                            ])
                        ])),
              ])),
      ]),
    );
  }
}
