import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../widgets/live_style.dart';
import 'live_watch_state.dart';

/// A presentation of an existing watch state, without another API/player owner.
class LiveFullscreenPage extends StatefulWidget {
  const LiveFullscreenPage({
    super.key,
    required this.state,
    required this.builder,
    required this.onPopped,
  });

  final LiveWatchState state;
  final WidgetBuilder builder;
  final VoidCallback onPopped;

  @override
  State<LiveFullscreenPage> createState() => _LiveFullscreenPageState();
}

class _LiveFullscreenPageState extends State<LiveFullscreenPage> {
  final _surface = Object();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.state.setSurfaceVisible(
        _surface, ModalRoute.of(context)?.isCurrent != false);
  }

  @override
  void dispose() {
    widget.state.removeSurface(_surface);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) widget.onPopped();
        },
        child: AppSystemBars(
          background: LiveStyle.screen,
          child: Scaffold(
            backgroundColor: LiveStyle.screen,
            body: SafeArea(child: widget.builder(context)),
          ),
        ),
      );
}
