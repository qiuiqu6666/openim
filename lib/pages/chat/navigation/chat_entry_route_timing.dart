import 'package:flutter/widgets.dart';

import 'chat_entry_trace.dart';

/// Route completion is independent of whether the message window is ready.
class ChatEntryRouteTiming extends StatefulWidget {
  const ChatEntryRouteTiming(
      {super.key, required this.trace, required this.child});
  final ChatEntryTrace? trace;
  final Widget child;
  @override
  State<ChatEntryRouteTiming> createState() => _ChatEntryRouteTimingState();
}

class _ChatEntryRouteTimingState extends State<ChatEntryRouteTiming>
    with WidgetsBindingObserver {
  ModalRoute<dynamic>? _route;
  Animation<double>? _animation;
  bool _reducedMotion = false;
  bool _scheduled = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_animation != _route?.animation) {
      _animation?.removeStatusListener(_status);
      _animation = _route?.animation;
      _animation?.addStatusListener(_status);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ChatEntryRouteTiming oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed) _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedule();
  }

  void _schedule() {
    if (_scheduled || widget.trace == null || widget.trace!.transitionFinished) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _route?.isCurrent == false) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      if (_reducedMotion || _animation == null || _animation!.isCompleted) {
        widget.trace?.mark('transition_finished');
      }
    });
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_status);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
