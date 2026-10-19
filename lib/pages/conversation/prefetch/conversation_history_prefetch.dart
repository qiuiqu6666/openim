import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../chat/history/chat_history_prefetcher.dart';

/// Speculates only on visible rows after the feed settles. No network reads.
class ConversationHistoryPrefetch extends StatefulWidget {
  const ConversationHistoryPrefetch(
      {super.key,
      required this.active,
      required this.sessionCurrent,
      required this.child,
      this.warmLocal});
  final Future<void> Function(ConversationInfo)? warmLocal;
  final bool active;
  final bool Function() sessionCurrent;
  final Widget child;

  @override
  State<ConversationHistoryPrefetch> createState() => _PrefetchState();
}

class _PrefetchState extends State<ConversationHistoryPrefetch>
    with WidgetsBindingObserver {
  final _visible = <Object, ConversationInfo>{};
  Timer? _settle;
  bool _foreground = true;
  bool _scrolling = false;
  bool _running = false;
  bool _dirty = false;
  bool _current = true;
  bool get _active =>
      mounted &&
      widget.active &&
      _foreground &&
      _current &&
      !_scrolling &&
      widget.sessionCurrent();

  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  void _changed(Object source, ConversationInfo? info) {
    if (info == null) {
      _visible.remove(source);
    } else {
      _visible[source] = info;
    }
    _schedule();
  }

  void _schedule() {
    _dirty = true;
    _settle?.cancel();
    if (_active && !_running) {
      _settle = Timer(const Duration(milliseconds: 150), _warm);
    }
  }

  Future<void> _warm() async {
    if (!_active || _running) return;
    _dirty = false;
    _running = true;
    final account = (OpenIM.iMManager.userID, OpenIM.iMManager.token);
    final candidates = _visible.entries.take(8).toList();
    var next = 0;
    Future<void> worker() async {
      while (_active &&
          next < candidates.length &&
          account == (OpenIM.iMManager.userID, OpenIM.iMManager.token)) {
        final entry = candidates[next++];
        if (!identical(_visible[entry.key], entry.value)) continue;
        await (widget.warmLocal ??
            ChatHistoryPrefetcher.shared.warmLocal)(entry.value);
      }
    }

    try {
      await Future.wait([worker(), worker()]);
    } finally {
      _running = false;
      if (mounted && _dirty) _schedule();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _current = ModalRoute.of(context)?.isCurrent != false;
    _schedule();
  }

  @override
  void didUpdateWidget(ConversationHistoryPrefetch oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  @override
  void didHaveMemoryPressure() {
    _settle?.cancel();
    _visible.clear();
    OpenIM.iMManager.messageManager.windowCache.invalidate();
  }

  @override
  void dispose() {
    _settle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PrefetchBinding(
      state: this,
      child: NotificationListener<ScrollNotification>(
          onNotification: (event) {
            if (event.depth == 0) {
              if (event is ScrollStartNotification) _scrolling = true;
              if (event is ScrollEndNotification) _scrolling = false;
              _schedule();
            }
            return false;
          },
          child: widget.child));
}

class _PrefetchBinding extends InheritedWidget {
  const _PrefetchBinding({required this.state, required super.child});
  final _PrefetchState state;
  @override
  bool updateShouldNotify(_PrefetchBinding oldWidget) =>
      state != oldWidget.state;
}

class ConversationHistoryPrefetchItem extends StatefulWidget {
  const ConversationHistoryPrefetchItem(
      {super.key, required this.conversation, required this.child});
  final ConversationInfo conversation;
  final Widget child;
  @override
  State<ConversationHistoryPrefetchItem> createState() => _ItemState();
}

class _ItemState extends State<ConversationHistoryPrefetchItem> {
  final _source = Object();
  _PrefetchState? _owner;
  bool _visible = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner =
        context.dependOnInheritedWidgetOfExactType<_PrefetchBinding>()?.state;
    if (owner != _owner) {
      _owner?._changed(_source, null);
      _owner = owner;
      if (_visible) _owner?._changed(_source, widget.conversation);
    }
  }

  @override
  void didUpdateWidget(ConversationHistoryPrefetchItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_visible) _owner?._changed(_source, widget.conversation);
  }

  @override
  void dispose() {
    _owner?._changed(_source, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VisibilityDetector(
      key: ObjectKey(_source),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        _visible = info.visibleFraction > 0;
        _owner?._changed(_source, _visible ? widget.conversation : null);
      },
      child: widget.child);
}
