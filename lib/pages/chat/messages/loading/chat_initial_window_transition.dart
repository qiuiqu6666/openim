import 'package:flutter/material.dart';

import 'chat_entry_loading_tokens.dart';
import 'chat_entry_paint_observer.dart';

/// Keeps the same real timeline mounted while a passive skeleton crossfades.
/// No message keys, scroll position, or list geometry are animated/replaced.
class ChatInitialWindowTransition extends StatefulWidget {
  const ChatInitialWindowTransition(
      {super.key,
      required this.loading,
      required this.skeleton,
      required this.child,
      this.onContentPainted,
      this.observePaint,
      this.onRevealed});
  final bool loading;
  final Widget skeleton;
  final Widget child;
  final VoidCallback? onRevealed;
  final void Function(bool interactive)? onContentPainted;
  final bool Function()? observePaint;

  @override
  ChatInitialWindowTransitionState createState() =>
      ChatInitialWindowTransitionState();
}

class ChatInitialWindowTransitionState
    extends State<ChatInitialWindowTransition>
    with SingleTickerProviderStateMixin {
  late final _reveal = AnimationController(
      vsync: this,
      duration: ChatEntryLoadingTokens.revealDuration,
      value: widget.loading ? 0 : 1)
    ..addStatusListener(_statusChanged);
  late final _contentOpacity =
      _reveal.drive(CurveTween(curve: ChatEntryLoadingTokens.revealCurve));
  late final _skeletonOpacity =
      _contentOpacity.drive(Tween(begin: 1.0, end: 0.0));
  late bool _showSkeleton = widget.loading;
  bool _reducedMotion = false;
  int _revision = 0;
  Duration? _loadingStartedAt;

  @override
  void initState() {
    super.initState();
    if (widget.loading) {
      _loadingStartedAt = WidgetsBinding.instance.currentFrameTimeStamp;
    }
  }

  bool get canReportContent => !widget.loading && _reveal.isCompleted;

  void _statusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || widget.loading || !mounted) {
      return;
    }
    if (_showSkeleton) setState(() => _showSkeleton = false);
    widget.onRevealed?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion) {
      _reveal.value = widget.loading ? 0 : 1;
      _showSkeleton = widget.loading;
    }
  }

  @override
  void didUpdateWidget(covariant ChatInitialWindowTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading == widget.loading) return;
    final revision = ++_revision;
    if (widget.loading) {
      _showSkeleton = true;
      _loadingStartedAt = WidgetsBinding.instance.currentFrameTimeStamp;
    } else {
      final waited = WidgetsBinding.instance.currentFrameTimeStamp -
          (_loadingStartedAt ?? Duration.zero);
      // A local proof arriving a frame after mounting should not incur the
      // same reveal delay as a visibly sustained remote loading state.
      _reveal.duration = waited <= ChatEntryLoadingTokens.briefLoadThreshold
          ? ChatEntryLoadingTokens.briefRevealDuration
          : ChatEntryLoadingTokens.revealDuration;
      _loadingStartedAt = null;
    }
    // Let the real viewport lay out and settle its initial latest edge before
    // revealing it. Retry/closure invalidates this callback, without a timer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _revision) return;
      if (_reducedMotion) {
        _reveal.value = widget.loading ? 0 : 1;
      } else if (widget.loading) {
        _reveal.reverse();
      } else {
        _reveal.forward();
      }
    });
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    final animation = Listenable.merge(
        [_reveal, route?.animation, navigator.userGestureInProgressNotifier]);
    return Stack(fit: StackFit.expand, children: [
      FadeTransition(
          opacity: _contentOpacity,
          child: IgnorePointer(
              ignoring: !canReportContent,
              child: ExcludeSemantics(
                  excluding: !canReportContent,
                  child: widget.onContentPainted == null
                      ? widget.child
                      : ChatEntryPaintObserver(
                          animation: animation,
                          shouldObserve: widget.observePaint ?? () => true,
                          onPainted: () {
                            final lifecycle =
                                WidgetsBinding.instance.lifecycleState;
                            if (!mounted ||
                                widget.loading ||
                                _reveal.value <= 0 ||
                                (!_reducedMotion &&
                                    route?.animation?.value == 0) ||
                                route?.isCurrent == false ||
                                (lifecycle != null &&
                                    lifecycle != AppLifecycleState.resumed)) {
                              return;
                            }
                            widget.onContentPainted?.call(canReportContent &&
                                route?.animation?.status !=
                                    AnimationStatus.reverse &&
                                !navigator.userGestureInProgress);
                          },
                          child: widget.child)))),
      if (_showSkeleton)
        Positioned.fill(
            child: IgnorePointer(
                child: FadeTransition(
                    opacity: _skeletonOpacity,
                    child: ExcludeSemantics(
                        excluding: !widget.loading, child: widget.skeleton)))),
    ]);
  }
}
