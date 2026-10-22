import 'package:flutter/material.dart';
import 'bingo_card.dart';
import 'bingo_controller.dart';

class BingoLiveCard extends StatefulWidget {
  const BingoLiveCard(
      {super.key,
      required this.controller,
      this.preview = false,
      this.showOpenHint = true});
  final BingoController controller;
  final bool preview;
  final bool showOpenHint;
  @override
  State<BingoLiveCard> createState() => _BingoLiveCardState();
}

class _BingoLiveCardState extends State<BingoLiveCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.attach();
    });
  }

  @override
  void didUpdateWidget(covariant BingoLiveCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.detach();
      widget.controller.attach();
    }
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (_, __) {
          final c = widget.controller;
          return BingoLatestCard(
            draw: c.current() ? c.draw : null,
            now: c.now,
            preview: widget.preview,
            showOpenHint: widget.showOpenHint,
            statusMessage: !c.current()
                ? '群类型或登录状态已变更'
                : c.error ?? (c.draw == null ? '正在加载宾果开奖…' : null),
            onRetry:
                c.error != null && !c.loading && c.current() ? c.refresh : null,
          );
        },
      );
}
