import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../data/agent_query_controller.dart';

/// Same-query refresh keeps the existing viewport mounted. Failures remain
/// actionable without replacing retained rows with a full-page error.
class AgentQueryFeedback extends StatefulWidget {
  const AgentQueryFeedback(
      {super.key,
      required this.state,
      required this.onRetry,
      required this.child});
  final AgentQueryController state;
  final VoidCallback onRetry;
  final Widget child;

  @override
  State<AgentQueryFeedback> createState() => _AgentQueryFeedbackState();
}

class _AgentQueryFeedbackState extends State<AgentQueryFeedback> {
  String? _lastError;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _notice;
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant AgentQueryFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state == widget.state) return;
    oldWidget.state.removeListener(_changed);
    _notice?.close();
    _notice = null;
    _lastError = null;
    widget.state.addListener(_changed);
  }

  void _changed() {
    final error = widget.state.error;
    if (error == _lastError) return;
    _lastError = error;
    if (error == null || widget.state.data == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.state.current ||
          widget.state.error != error ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      _notice?.close();
      _notice = ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            zh ? '刷新失败，已保留上次结果' : 'Refresh failed. Previous results are kept.'),
        action: SnackBarAction(
            label: zh ? '重试' : 'Retry', onPressed: widget.onRetry),
      ));
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    _notice?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        widget.child,
        if (widget.state.loading && widget.state.data != null)
          const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SizedBox(
                  height: AppTokens.s2, child: LinearProgressIndicator())),
      ]);
}
