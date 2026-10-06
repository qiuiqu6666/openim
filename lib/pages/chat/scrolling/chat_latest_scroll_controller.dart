import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'chat_latest_scroll_tokens.dart';

/// Owns explicit returns to latest and coalesces automatic following requests.
/// Focus remains owned by the composer; only a user drag cancels a return.
class ChatLatestScrollController {
  ChatLatestScrollController({
    required this.controller,
    required this.isClosed,
    required this.shouldFollow,
    required this.onReachedLatest,
  });

  final ScrollController controller;
  final bool Function() isClosed;
  final bool Function() shouldFollow;
  final VoidCallback onReachedLatest;
  bool _closed = false;
  bool _scheduled = false;
  bool _forced = false;
  bool _animated = false;
  bool _returning = false;
  int _revision = 0;

  bool get _active => !_closed && !isClosed() && controller.hasClients;

  void request({bool force = true, bool animated = false}) {
    if (_closed || isClosed() || (!force && _returning)) return;
    if (force || !_forced) _animated = animated;
    _forced = _forced || force;
    if (_scheduled) return;
    _scheduled = true;
    final revision = _revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (revision != _revision) return;
      final force = _forced;
      final animated = _animated;
      _scheduled = false;
      _forced = false;
      _animated = false;
      if (!_active || (!force && !shouldFollow())) return;
      if (animated &&
          !WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
              .disableAnimations &&
          _distance > ChatLatestScrollTokens.distanceEpsilon) {
        unawaited(_returnSmoothly(++_revision));
      } else {
        cancel();
        controller.jumpTo(controller.position.minScrollExtent);
        if (force) onReachedLatest();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  double get _distance =>
      controller.position.pixels - controller.position.minScrollExtent;

  bool _current(int revision) => _active && revision == _revision;

  Future<void> _returnSmoothly(int revision) async {
    _returning = true;
    try {
      // Keyboard layout and lazy, variable-height rows can refine the target
      // during animation. Re-read the painted edge rather than assuming zero.
      for (var attempt = 0;
          attempt < ChatLatestScrollTokens.correctionAttempts &&
              _current(revision);
          attempt++) {
        if (_distance.abs() <= ChatLatestScrollTokens.distanceEpsilon) break;
        await controller.animateTo(
          controller.position.minScrollExtent,
          duration: attempt == 0
              ? ChatLatestScrollTokens.durationFor(
                  _distance, controller.position.viewportDimension)
              : ChatLatestScrollTokens.correctionDuration,
          curve: ChatLatestScrollTokens.curve,
        );
        if (!_current(revision)) return;
        await SchedulerBinding.instance.endOfFrame;
      }
      if (!_current(revision) ||
          _distance.abs() > ChatLatestScrollTokens.distanceEpsilon) {
        return;
      }
      // Finalize on the real edge; the viewport can then choose its latest
      // stable center. Never turn a drifting target into a visible final jump.
      controller.jumpTo(controller.position.minScrollExtent);
      onReachedLatest();
    } finally {
      if (revision == _revision) _returning = false;
    }
  }

  /// Flutter's drag activity stops animateTo; invalidate its completion too.
  void cancel() {
    _revision++;
    _scheduled = false;
    _forced = false;
    _animated = false;
    _returning = false;
  }

  void close() {
    _closed = true;
    cancel();
  }
}
