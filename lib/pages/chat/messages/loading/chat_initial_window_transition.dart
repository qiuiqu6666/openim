import 'dart:async';

import 'package:flutter/material.dart';

import 'chat_entry_loading_tokens.dart';
import 'chat_entry_paint_observer.dart';

/// Keeps the real timeline mounted and reveals it immediately when ready.
/// No message keys, scroll position, or list geometry are animated/replaced.
class ChatInitialWindowTransition extends StatefulWidget {
  const ChatInitialWindowTransition(
      {super.key,
      required this.loading,
      required this.loadingIndicator,
      required this.child,
      this.onContentPainted,
      this.observePaint,
      this.onRevealed});
  final bool loading;
  final Widget loadingIndicator;
  final Widget child;
  final VoidCallback? onRevealed;
  final void Function(bool interactive)? onContentPainted;
  final bool Function()? observePaint;

  @override
  ChatInitialWindowTransitionState createState() =>
      ChatInitialWindowTransitionState();
}

class ChatInitialWindowTransitionState
    extends State<ChatInitialWindowTransition> {
  Timer? _loadingTimer;
  bool _showLoading = false;
  int _revision = 0;

  bool get canReportContent => !widget.loading;

  @override
  void initState() {
    super.initState();
    if (widget.loading) _scheduleLoading();
  }

  void _scheduleLoading() {
    _loadingTimer?.cancel();
    _loadingTimer = Timer(ChatEntryLoadingTokens.loadingHintDelay, () {
      if (mounted && widget.loading) setState(() => _showLoading = true);
    });
  }

  @override
  void didUpdateWidget(covariant ChatInitialWindowTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading == widget.loading) return;
    final revision = ++_revision;
    _loadingTimer?.cancel();
    _showLoading = false;
    if (widget.loading) {
      _scheduleLoading();
    } else {
      // Refresh viewport receipts after actual layout, without delaying paint.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && revision == _revision && !widget.loading) {
          widget.onRevealed?.call();
        }
      });
    }
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    final animation = Listenable.merge(
        [route?.animation, navigator.userGestureInProgressNotifier]);
    return Stack(fit: StackFit.expand, children: [
      Opacity(
          opacity: widget.loading ? 0 : 1,
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
                                (route?.animation?.value == 0 &&
                                    !MediaQuery.disableAnimationsOf(context)) ||
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
      if (_showLoading && widget.loading)
        Positioned.fill(child: IgnorePointer(child: widget.loadingIndicator)),
    ]);
  }
}
