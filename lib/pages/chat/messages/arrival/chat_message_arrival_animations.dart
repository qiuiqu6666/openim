import 'package:flutter/material.dart';

import 'chat_message_arrival_controller.dart';
import 'chat_message_arrival_tokens.dart';
import 'chat_message_arrival_viewport_slide.dart';

/// One list owns each entrance, so replacing the viewport's sliver center does
/// not restart an older message when another message arrives during its motion.
class ChatMessageArrivalAnimations {
  ChatMessageArrivalAnimations({required this.vsync, required this.arrivals});

  final TickerProvider vsync;
  final ChatMessageArrivalController arrivals;
  final _animations = <String, AnimationController>{};
  final _enteredIDs = <String>{};
  final _geometry = ChatMessageArrivalGeometry();

  void sync(Set<String> ids, {required bool enabled}) {
    arrivals.retain(ids);
    _enteredIDs.retainAll(ids);
    for (final id in _animations.keys.toList(growable: false)) {
      final animation = _animations[id]!;
      if (!ids.contains(id) || !arrivals.isEntering(id)) {
        _animations.remove(id);
        arrivals.finish(id);
        animation.value = 1;
        animation.dispose();
      } else if (!enabled || arrivals.isCancelled(id)) {
        animation.value = 1;
      }
    }
    for (final id in arrivals.takePending(ids)) {
      if (!enabled) {
        arrivals.finish(id);
        continue;
      }
      final animation = AnimationController(
          vsync: vsync, duration: ChatMessageArrivalTokens.duration);
      _animations[id] = animation;
      _enteredIDs.add(id);
      animation.addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        _finishAfterPaint(id, animation);
      });
      animation.forward();
    }
    // The SDK set retains the timeline's newest-to-oldest insertion order.
    // Active rows alone can displace a younger entrance; settled rows already
    // occupy their normal layout extent and need no retained render reference.
    _geometry.sync(ids, _animations.keys.toSet());
  }

  void _finishAfterPaint(String id, AnimationController animation) {
    // Status completes before layout. The final painted geometry, including
    // any older entrance ahead of this row, must settle before releasing reads.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(_animations[id], animation)) return;
      if (_geometry.isSettled(id)) {
        arrivals.finish(id, notify: true);
      } else {
        _finishAfterPaint(id, animation);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget wrap(String id, Widget child) {
    return !_enteredIDs.contains(id)
        ? child
        : ChatMessageArrivalTransition(
            messageID: id,
            geometry: _geometry,
            // Keep the same widget/render structure after releasing its ticker.
            // Media state must survive the entrance's final painted frame.
            animation: _animations[id] ?? const AlwaysStoppedAnimation(1.0),
            child: child);
  }

  void dispose() {
    for (final entry in _animations.entries) {
      arrivals.finish(entry.key);
      entry.value.dispose();
    }
    _animations.clear();
    _enteredIDs.clear();
    _geometry.dispose();
  }
}

class ChatMessageArrivalTransition extends StatelessWidget {
  const ChatMessageArrivalTransition(
      {super.key,
      required this.messageID,
      required this.geometry,
      required this.animation,
      required this.child});

  final String messageID;
  final ChatMessageArrivalGeometry geometry;
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) => ChatMessageArrivalViewportSlide(
        messageID: messageID,
        geometry: geometry,
        progress: ChatMessageArrivalTokens.curve.transform(animation.value),
        extent: ChatMessageArrivalTokens.extentCurve.transform(animation.value),
        outsideGap: ChatMessageArrivalTokens.outsideGap,
        child: child!,
      ),
    );
  }
}
