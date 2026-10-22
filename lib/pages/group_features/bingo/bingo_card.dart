import 'package:flutter/material.dart';
import '../mark_six/widgets/mark_six_style.dart';
import '../mark_six/widgets/mark_six_latest_card.dart';
import 'bingo_draw.dart';

// The card heading shows the following period; result metadata stays unchanged.
String _cardIssue(BingoDraw? draw) {
  final issue = BigInt.tryParse(draw?.issue ?? '');
  return issue == null
      ? '—'
      : (issue + BigInt.one).toString().padLeft(draw!.issue.length, '0');
}

class BingoLatestCard extends StatelessWidget {
  const BingoLatestCard(
      {super.key,
      this.draw,
      this.onOpenHistory,
      this.preview = false,
      this.showOpenHint = true,
      this.now,
      this.statusMessage,
      this.onRetry});

  final BingoDraw? draw;
  final VoidCallback? onOpenHistory;
  final bool preview;
  final bool showOpenHint;
  final DateTime? now;
  final String? statusMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (preview) {
      return _BingoCompactPreview(
          draw: draw,
          now: now,
          statusMessage: statusMessage,
          onRetry: onRetry,
          showOpenHint: showOpenHint);
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final displayNow = now ?? draw?.serverTime;
    return Container(
      key: const ValueKey('bingo-latest-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          scheme.surface,
          scheme.primaryContainer.withValues(alpha: .42),
        ]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.primary.withValues(alpha: .18)),
        boxShadow: [
          BoxShadow(
              color: scheme.primary.withValues(alpha: .08),
              blurRadius: 18,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  scheme.primary.withValues(alpha: .65),
                  scheme.primary
                ]),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.bolt_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('最新开奖',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          ),
          Text('第 ${_cardIssue(draw)} 期',
              style: const TextStyle(
                  color: Color(0xFFF52D50),
                  fontSize: 19,
                  fontWeight: FontWeight.w800)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 16),
          child: Row(children: [
            Expanded(
              child: Text(
                  '当前时间 ${displayNow == null ? '—' : formatBingoTime(displayNow)}',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
            Text(bingoCountdown(draw, displayNow),
                style: TextStyle(
                    color: scheme.primary, fontWeight: FontWeight.w700)),
          ]),
        ),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: _BingoNumberArea(draw: draw),
          ),
        ),
        const SizedBox(height: 14),
        if (statusMessage != null)
          TextButton(onPressed: onRetry, child: Text(statusMessage!)),
        if (onOpenHistory != null)
          Semantics(
            button: onOpenHistory != null,
            child: InkWell(
              onTap: onOpenHistory,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: scheme.primary.withValues(alpha: .18)),
                  color: scheme.surface.withValues(alpha: .8),
                ),
                child: Row(children: [
                  Icon(Icons.bar_chart_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('点击卡片 · 全屏查看开奖记录')),
                  Icon(Icons.arrow_forward_rounded, color: scheme.primary),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _BingoCompactPreview extends StatelessWidget {
  const _BingoCompactPreview(
      {this.draw,
      this.now,
      this.statusMessage,
      this.onRetry,
      this.showOpenHint = true});
  final bool showOpenHint;
  final BingoDraw? draw;
  final DateTime? now;
  final String? statusMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    final displayNow = now ?? draw?.serverTime;
    return Container(
      key: const ValueKey('bingo-latest-card'),
      height: (showOpenHint ? 180 : 164) *
          MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [style.lotteryPanel, style.lotteryAlt]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.lotteryBorder),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1F17243D), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Stack(children: [
        Positioned(
          right: 6,
          bottom: 8,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Opacity(
                opacity: style.dark ? .14 : .20,
                child: Image.asset(
                    'lib/pages/group_features/bingo/assets/latest_card_watermark.png',
                    width: 96,
                    height: 96),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Column(children: [
            Row(children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                      colors: [Color(0xFF61A8FF), Color(0xFF176EF2)]),
                ),
                child: const Icon(Icons.bolt_rounded,
                    color: Colors.white, size: 19),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('最新开奖',
                      style: TextStyle(
                          color: style.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800))),
              Text('第 ${_cardIssue(draw)} 期',
                  style: const TextStyle(
                      color: MarkSixStyle.red,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              Expanded(
                  child: Text(
                      '当前时间 ${displayNow == null ? '—' : formatBingoTime(displayNow)}',
                      style: TextStyle(color: style.secondary, fontSize: 11))),
              Text(bingoCountdown(draw, displayNow),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 11)),
            ]),
            const SizedBox(height: 4),
            Expanded(
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                child: _BingoNumberArea(draw: draw),
              ),
            ),
            const SizedBox(height: 4),
            Visibility(
                visible: showOpenHint || statusMessage != null,
                child: Semantics(
                  button: onRetry != null,
                  child: GestureDetector(
                    onTap: onRetry,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                        statusMessage ??
                            (showOpenHint ? '点击卡片 · 全屏查看开奖记录' : ''),
                        style: TextStyle(
                            fontSize: 11,
                            color: style.secondary,
                            fontWeight: FontWeight.w500)),
                  ),
                )),
          ]),
        ),
      ]),
    );
  }
}

class _BingoNumberArea extends StatelessWidget {
  const _BingoNumberArea({this.draw});
  final BingoDraw? draw;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: 580,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
                padding: EdgeInsets.only(left: 2),
                child: _BingoPill(text: '平码', color: Colors.blue)),
            const SizedBox(height: 7),
            Row(children: [
              for (var i = 0; i < 6; i++)
                Padding(
                  padding: EdgeInsets.only(right: i == 5 ? 0 : 8),
                  child: _BallColumn(
                    ball: draw != null && i < draw!.regular.length
                        ? draw!.regular[i]
                        : null,
                    fallbackColor: const [
                      Colors.blue,
                      Colors.green,
                      Colors.red,
                      Colors.orange,
                      Colors.purple,
                      Colors.blue
                    ][i],
                  ),
                ),
            ]),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 16, 0),
            child: SizedBox(
                height: 90,
                child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: MarkSixStyle.of(context).lotteryBorder)),
          ),
          Column(children: [
            const _BingoPill(text: '特码', color: Colors.red),
            const SizedBox(height: 5),
            _BallColumn(
                ball: draw?.special, fallbackColor: Colors.red, special: true),
          ]),
          const Spacer(),
        ],
      ));
}

class _BingoPill extends StatelessWidget {
  const _BingoPill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w700)),
      );
}

class _BallColumn extends StatelessWidget {
  const _BallColumn(
      {required this.ball, required this.fallbackColor, this.special = false});

  final BingoBall? ball;
  final Color fallbackColor;
  final bool special;

  @override
  Widget build(BuildContext context) {
    final size = special ? 80.0 : 60.0;
    if (ball == null) {
      return ExcludeSemantics(
        child: SizedBox(
          width: size,
          child: Column(children: [
            _BingoSkeleton(width: size, height: size, circular: true),
            const SizedBox(height: 8),
            const _BingoSkeleton(width: 36, height: 26),
          ]),
        ),
      );
    }
    final color = ball?.color ?? fallbackColor;
    final wave = color == Colors.blue
        ? '蓝'
        : color == Colors.green
            ? '绿'
            : color == Colors.grey
                ? ''
                : '红';
    final tint =
        color == Colors.orange || color == Colors.purple ? color : null;
    final labelColor = tint ?? markSixWaveColor(wave);
    return SizedBox(
      width: special ? 80 : 60,
      child: Column(children: [
        MarkSixNumberBall(
            number: ball?.number.toString().padLeft(2, '0') ?? '—',
            wave: wave,
            tint: tint,
            size: size),
        const SizedBox(height: 8),
        _BingoPill(text: ball?.zodiac ?? '—', color: labelColor),
      ]),
    );
  }
}

/// Static, low-contrast placeholders avoid motion and keep the result layout.
class _BingoSkeleton extends StatelessWidget {
  const _BingoSkeleton(
      {required this.width, required this.height, this.circular = false});

  final double width;
  final double height;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: style.dark ? .16 : .07),
            color.withValues(alpha: style.dark ? .25 : .13),
            color.withValues(alpha: style.dark ? .18 : .08),
          ],
        ),
      ),
    );
  }
}
