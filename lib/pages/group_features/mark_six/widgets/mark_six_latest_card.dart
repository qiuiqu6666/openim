// Layout and art adapted from 99chat lottery_dashboard.dart.
// Source: https://github.com/qiuiqu6666/99chat (Apache-2.0).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../data/mark_six_controller.dart';
import 'mark_six_style.dart';

const markSixAssetPath = 'lib/pages/group_features/mark_six/assets/';

Color markSixWaveColor(String wave) => switch (wave) {
      '红' => MarkSixStyle.red,
      '蓝' => MarkSixStyle.blue,
      '绿' => MarkSixStyle.green,
      _ => AppTokens.textSecondaryLight,
    };

class MarkSixNumberBall extends StatelessWidget {
  const MarkSixNumberBall(
      {super.key, required this.number, required this.wave, this.size = 32});
  final String number;
  final String wave;
  final double size;
  @override
  Widget build(BuildContext context) {
    final asset = switch (wave) {
      '红' => 'hong.png',
      '蓝' => 'lan.png',
      '绿' => 'lv.png',
      _ => null
    };
    return SizedBox.square(
        dimension: size,
        child: Stack(alignment: Alignment.center, children: [
          if (asset != null)
            Image.asset('$markSixAssetPath$asset', width: size, height: size)
          else
            DecoratedBox(
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MarkSixStyle.of(context).alternate),
                child: SizedBox.square(dimension: size)),
          Text(number,
              style: TextStyle(
                  fontSize: size == 52
                      ? 25
                      : size == 60
                          ? 28
                          : size * .44,
                  fontWeight: FontWeight.w800,
                  color: asset == null
                      ? MarkSixStyle.of(context).text
                      : AppTokens.textPrimaryLight)),
        ]));
  }
}

class MarkSixLatestCard extends StatefulWidget {
  const MarkSixLatestCard(
      {super.key, required this.controller, this.preview = false});
  final MarkSixController controller;
  final bool preview;
  @override
  State<MarkSixLatestCard> createState() => _MarkSixLatestCardState();
}

class _MarkSixLatestCardState extends State<MarkSixLatestCard> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.current) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get countdown {
    final round = widget.controller.currentRound;
    if (round == null) return '期数待更新';
    if (round.status == 'drawn') return '已开奖';
    if (round.status == 'closed' || round.status == 'drawing') return '正在开奖';
    final stamp = round.raw['closeAt'] ?? round.raw['drawAt'];
    if (stamp is! num) return round.status == 'open' ? '投注中' : '等待开奖';
    final seconds =
        (DateTime.fromMillisecondsSinceEpoch(stamp.toInt(), isUtc: true)
                .difference(widget.controller.now())
                .inSeconds)
            .clamp(0, 86400);
    return '${round.status == 'open' ? '封盘' : '开奖'} ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final style = MarkSixStyle.of(context);
    if (!c.current) return const MarkSixEmpty(message: '登录状态已变更');
    if (!c.ready && c.loading) {
      return Center(child: LoadingView.indicator());
    }
    if (!c.ready) {
      return MarkSixEmpty(
          message: c.error ?? '暂无开奖数据', onRetry: () => c.refresh(force: true));
    }
    final latest = c.latest;
    final now = c.now().add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    return DefaultTextStyle.merge(
        style: TextStyle(color: style.text),
        child: Container(
            key: const ValueKey('lottery-latest-card'),
            padding: EdgeInsets.fromLTRB(12, 10, 12, widget.preview ? 8 : 10),
            decoration: BoxDecoration(
                gradient: widget.preview
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                            style.lotteryPanel,
                            style.dark ? style.lotteryPanel : style.lotteryAlt
                          ]),
                borderRadius: BorderRadius.circular(MarkSixStyle.radius),
                border: widget.preview
                    ? null
                    : Border.all(color: style.lotteryBorder),
                boxShadow: widget.preview
                    ? null
                    : [
                        BoxShadow(
                            color: style.dark
                                ? Colors.transparent
                                : const Color(0x141A67C9),
                            blurRadius: 18,
                            offset: const Offset(0, 7))
                      ]),
            child: Stack(clipBehavior: Clip.none, children: [
              if (!widget.preview)
                Positioned(
                    right: 6,
                    bottom: 8,
                    child: IgnorePointer(
                        child: ExcludeSemantics(
                            child: Opacity(
                                opacity: style.dark ? .14 : .20,
                                child: Image.asset(
                                    '${markSixAssetPath}latest_card_watermark.png',
                                    key: const ValueKey(
                                        'lottery-latest-watermark'),
                                    width: 96,
                                    height: 96,
                                    fit: BoxFit.contain))))),
              Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: const LinearGradient(colors: [
                                Color(0xFF61A8FF),
                                Color(0xFF176EF2)
                              ])),
                          child: const Icon(Icons.bolt_rounded,
                              color: AppTokens.onAccent, size: 19)),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('最新开奖',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800))),
                      Text('第 ${c.currentRound?.issue ?? '—'} 期',
                          style: const TextStyle(
                              color: MarkSixStyle.red,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 2),
                    Row(children: [
                      Expanded(
                          child: Text(
                              '当前时间 ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}',
                              style: TextStyle(
                                  fontSize: 11, color: style.secondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 4),
                      Text(countdown,
                          style: TextStyle(
                              fontSize: 11,
                              color: c.currentRound?.status == 'open'
                                  ? style.primary
                                  : MarkSixStyle.red)),
                    ]),
                    const SizedBox(height: 8),
                    if (latest == null)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text('暂无已开奖记录',
                              style: TextStyle(color: style.secondary)))
                    else
                      Row(children: [
                        MarkSixNumberBall(
                            number: latest.number,
                            wave: latest.wave,
                            size: widget.preview ? 52 : 60),
                        SizedBox(width: widget.preview ? 10 : 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('特码 ${latest.number} · ${latest.zodiac}',
                                  style: TextStyle(
                                      fontSize: widget.preview ? 16 : 17,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 7),
                              Wrap(spacing: 5, runSpacing: 5, children: [
                                for (final value in [
                                  latest.value('parity'),
                                  latest.value('size'),
                                  '${latest.value('head')}头',
                                  '${latest.value('tail')}尾',
                                  '合${latest.value('sumParity')}',
                                  latest.value('fiveElement'),
                                  '${latest.wave}波'
                                ])
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: style.lotteryAlt,
                                          borderRadius:
                                              BorderRadius.circular(6)),
                                      child: Text(value,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: style.secondary))),
                              ]),
                            ])),
                      ]),
                  ])
            ])));
  }
}
