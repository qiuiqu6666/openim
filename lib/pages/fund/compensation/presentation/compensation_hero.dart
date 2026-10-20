import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import '../models/compensation_detail.dart';
import 'compensation_tokens.dart';
import 'compensation_artwork.dart';

class CompensationHero extends StatelessWidget {
  const CompensationHero(
      {super.key, required this.detail, required this.state});
  final CompensationDetail detail;
  final CompensationState? state;

  @override
  Widget build(BuildContext context) {
    final illustratedState = state == CompensationState.unclaimed ||
        state == CompensationState.ended;
    final received = state == CompensationState.claimed;
    final accent = CompensationTokens.accent(context);
    final label = switch (state) {
      CompensationState.claimed => AppCopy.text('已领取'),
      CompensationState.ended => AppCopy.text('活动已截止'),
      CompensationState.ineligible => AppCopy.text('暂无参与资格'),
      _ => AppCopy.text('未领取'),
    };
    final largeText =
        MediaQuery.textScalerOf(context).scale(CompensationTokens.body) >
            CompensationTokens.body * 1.3;
    final reward = Column(mainAxisSize: MainAxisSize.min, children: [
      Text(AppCopy.text('恭喜获得老用户补偿'),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: CompensationTokens.invitationInk,
              fontSize: CompensationTokens.label,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: CompensationTokens.small),
      Text.rich(
          TextSpan(children: [
            TextSpan(text: detail.amount),
            TextSpan(
                text: AppCopy.text(' 99币'),
                style: TextStyle(fontSize: CompensationTokens.body))
          ]),
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: CompensationTokens.red,
              fontSize: CompensationTokens.rewardAmount,
              fontWeight: FontWeight.w900)),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (largeText) ...[
        Semantics(
            header: true,
            label: AppCopy.format('{#0}，感谢你一直都在', [detail.title]),
            child: const CompensationArtwork.states(
                Rect.fromLTWH(0, 0, 1222, 220))),
        Text(AppCopy.format('老用户补偿总奖池 {#0}', [detail.poolLabel]),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: accent,
                fontSize: CompensationTokens.posterTitle,
                fontWeight: FontWeight.w800)),
      ] else
        LayoutBuilder(
            builder: (context, box) => Stack(children: [
                  Semantics(
                      header: true,
                      label: AppCopy.format('{#0}，感谢你一直都在', [detail.title]),
                      child: const CompensationArtwork.states(
                          CompensationArtwork.stateHeader)),
                  Positioned(
                      top: box.maxWidth * .205,
                      left: box.maxWidth * .29,
                      right: box.maxWidth * .28,
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(children: [
                            Text(AppCopy.text('老用户补偿总奖池'),
                                style: TextStyle(
                                    color: CompensationTokens.invitationInk,
                                    fontSize: CompensationTokens.label,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(width: CompensationTokens.gap),
                            Text(detail.poolLabel,
                                style: const TextStyle(
                                    color: CompensationTokens.red,
                                    fontSize: CompensationTokens.posterTitle,
                                    fontWeight: FontWeight.w900)),
                          ]))),
                ])),
      if (illustratedState)
        LayoutBuilder(
            builder: (context, box) =>
                Stack(alignment: Alignment.bottomCenter, children: [
                  Positioned(
                      left: 0,
                      bottom: box.maxWidth * .08,
                      width: box.maxWidth * .30,
                      child:
                          const CompensationArtwork(CompensationArtwork.gift)),
                  Positioned(
                      right: 0,
                      bottom: box.maxWidth * .08,
                      width: box.maxWidth * .30,
                      child: const CompensationArtwork.states(
                          CompensationArtwork.stateGift,
                          original: true)),
                  Semantics(
                      label: label,
                      child: SizedBox(
                          width: box.maxWidth * .64,
                          child: CompensationArtwork.states(
                              state == CompensationState.ended
                                  ? CompensationArtwork.stateEnded
                                  : CompensationArtwork.stateClosed,
                              original: true))),
                ]))
      else
        LayoutBuilder(
            builder: (context, constraints) =>
                Stack(alignment: Alignment.topCenter, children: [
                  if (received)
                    Transform.translate(
                        offset: Offset(
                            constraints.maxWidth *
                                .86 *
                                (.5 -
                                    CompensationArtwork.envelopeCenterX /
                                        CompensationArtwork.envelope.width),
                            0),
                        child: SizedBox(
                            width: constraints.maxWidth * .86,
                            child: const CompensationArtwork(
                                CompensationArtwork.envelope)))
                  else
                    Image.asset(CompensationTokens.closedAsset,
                        width: constraints.maxWidth,
                        height: constraints.maxWidth * .68,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true),
                  if (received && !largeText)
                    Positioned(
                        top: constraints.maxWidth * .14,
                        left: constraints.maxWidth * .265,
                        right: constraints.maxWidth * .265,
                        child: FittedBox(fit: BoxFit.scaleDown, child: reward)),
                ])),
      if (received && largeText)
        Container(
            padding: const EdgeInsets.all(CompensationTokens.gap),
            decoration: BoxDecoration(
                color: CompensationTokens.posterText,
                borderRadius: BorderRadius.circular(CompensationTokens.radius)),
            child: reward),
      if (!illustratedState || largeText)
        Center(
            child: Semantics(
                liveRegion: true,
                child: SizedBox(
                    width: CompensationTokens.heroHeight,
                    child: Stack(alignment: Alignment.center, children: [
                      CompensationArtwork(received
                          ? CompensationArtwork.claimed
                          : state == CompensationState.ended
                              ? CompensationArtwork.ended
                              : CompensationArtwork.unclaimed),
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                              start: CompensationTokens.heroHeight *
                                  (received || state == CompensationState.ended
                                      ? .42
                                      : .10),
                              end: CompensationTokens.heroHeight * .10,
                              top: CompensationTokens.gap,
                              bottom: CompensationTokens.gap),
                          child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(label,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: CompensationTokens.posterText,
                                      fontSize: CompensationTokens.posterTitle,
                                      fontWeight: FontWeight.w800))),
                        ),
                      ),
                    ])))),
      const SizedBox(height: CompensationTokens.gap),
      Text(
          switch (state) {
            CompensationState.claimed => AppCopy.text('补偿已发放至您的99币钱包'),
            CompensationState.ended => AppCopy.text('未领取份额自动退回平台资金池'),
            CompensationState.ineligible => AppCopy.text('当前账号不在本次活动邀请名单内'),
            _ => AppCopy.text('专属补偿红包，感谢你的陪伴'),
          },
          textAlign: TextAlign.center,
          style: TextStyle(
              color: accent,
              fontSize: CompensationTokens.body,
              fontWeight: FontWeight.w700)),
      if (received)
        Padding(
            padding: const EdgeInsets.only(top: CompensationTokens.gap),
            child: Text(
                AppCopy.format(
                    '领取时间：{#0}', [formatCompensationDate(detail.claimedAt!)]),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: CompensationTokens.label))),
    ]);
  }
}

String formatCompensationDate(DateTime date) {
  final d = date.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}.${two(d.month)}.${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)} (UTC+8)';
}
