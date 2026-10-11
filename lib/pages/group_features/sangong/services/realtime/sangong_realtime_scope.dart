import 'package:flutter/widgets.dart';

import '../../sangong_scope.dart';

/// A visible surface owns one share of its group's realtime calibration.
/// The route overlay disables TickerMode for maintained, opaque-covered pages;
/// transparent business dialogs keep the underlying surface active.
class SangongRealtimeScope extends StatefulWidget {
  const SangongRealtimeScope({
    super.key,
    required this.runtime,
    required this.child,
  });

  final SangongRuntime runtime;
  final Widget child;

  @override
  State<SangongRealtimeScope> createState() => _SangongRealtimeScopeState();
}

class _SangongRealtimeScopeState extends State<SangongRealtimeScope> {
  bool _visible = false;
  bool _acquired = false;

  @override
  void initState() {
    super.initState();
    widget.runtime.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(SangongRealtimeScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.runtime, widget.runtime)) return;
    oldWidget.runtime.removeListener(_sync);
    if (_acquired) oldWidget.runtime.realtime.release();
    _acquired = false;
    widget.runtime.addListener(_sync);
    _sync();
  }

  void _sync() {
    final active = _visible && widget.runtime.canManage;
    if (active == _acquired) return;
    _acquired = active;
    if (active) {
      widget.runtime.realtime.acquire();
    } else {
      widget.runtime.realtime.release();
    }
  }

  @override
  void dispose() {
    widget.runtime.removeListener(_sync);
    if (_acquired) widget.runtime.realtime.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SangongScope(runtime: widget.runtime, child: widget.child);
}
