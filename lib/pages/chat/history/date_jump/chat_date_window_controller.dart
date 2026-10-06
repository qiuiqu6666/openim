import 'package:flutter/scheduler.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../chat_timeline_controller.dart';

/// Coordinates history positions with the current chat's latest edge.
/// The timeline owns SDK windows; the viewport owns row measurements.
class ChatDateWindowController {
  ChatDateWindowController({
    required this.timeline,
    required this.positions,
    required this.isClosed,
    required this.cancelLatestScroll,
    required this.updateScrollOffset,
    required this.distanceFromLatest,
    required this.requestLatestScroll,
  });

  final ChatTimelineController timeline;
  final ChatListPositionController positions;
  final bool Function() isClosed;
  final void Function() cancelLatestScroll;
  final void Function(double) updateScrollOffset;
  final double Function() distanceFromLatest;
  final void Function(bool smooth) requestLatestScroll;
  final seeking = false.obs;
  final returning = false.obs;
  int _revision = 0;
  Future<bool>? _latestRequest;
  Future<bool> Function()? _failedAction;

  bool get buffering =>
      seeking.value || returning.value || timeline.viewingHistory.value;

  Future<bool> jumpToMessage(Message target) async {
    if (isClosed() || target.clientMsgID?.isNotEmpty != true) return false;
    _failedAction = null;
    final wasReturning = returning.value;
    timeline.cancelWindowChange();
    returning.value = false;
    _latestRequest = null;
    final revision = ++_revision;
    cancelLatestScroll();
    positions.cancel();
    seeking.value = true;
    updateScrollOffset(2);
    bool current() => !isClosed() && revision == _revision;
    var succeeded = false;
    try {
      final loaded = timeline.hasLoadedHistory &&
          !timeline.historyLoading.value &&
          timeline.messageList
              .any((message) => message.clientMsgID == target.clientMsgID);
      if ((!loaded || wasReturning) && !await timeline.jumpTo(target)) {
        return false;
      }
      // A loaded target can have arrived before its row identities rebuilt.
      // Position against the next painted list in both paths.
      await SchedulerBinding.instance.endOfFrame;
      if (!current()) return false;
      succeeded = await positions.jumpToMessage(target.clientMsgID!);
      return succeeded && current();
    } catch (_) {
      return false;
    } finally {
      if (current()) {
        if (!succeeded) _failedAction = () => jumpToMessage(target);
        seeking.value = false;
        if (!timeline.viewingHistory.value) timeline.flushBuffered();
        updateScrollOffset(
            timeline.viewingHistory.value ? 2 : distanceFromLatest());
      }
    }
  }

  Future<bool> returnToLatest({bool smooth = false}) {
    if (isClosed()) return Future.value(false);
    if (_latestRequest != null) return _latestRequest!;
    _failedAction = null;
    timeline.cancelWindowChange();
    if (!timeline.viewingHistory.value && !returning.value) {
      _revision++;
      positions.cancel();
      seeking.value = false;
      timeline.flushBuffered();
      requestLatestScroll(smooth);
      return Future.value(true);
    }
    final request = _returnToLatest(smooth);
    _latestRequest = request;
    request.then((_) {
      if (identical(_latestRequest, request)) _latestRequest = null;
    });
    return request;
  }

  Future<bool> _returnToLatest(bool smooth) async {
    final revision = ++_revision;
    cancelLatestScroll();
    positions.cancel();
    seeking.value = false;
    returning.value = true;
    bool current() => !isClosed() && revision == _revision;
    var succeeded = false;
    try {
      if (!await timeline.returnToLatest() || !current()) return false;
      timeline.flushBuffered();
      requestLatestScroll(smooth);
      succeeded = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      if (current()) {
        if (!succeeded) {
          _failedAction = () => returnToLatest(smooth: smooth);
        }
        returning.value = false;
        if (!timeline.viewingHistory.value) {
          timeline.flushBuffered();
          updateScrollOffset(distanceFromLatest());
        }
      }
    }
  }

  /// A failed window change includes its viewport action. Paging retries keep
  /// their existing direction, and reconnect live arrivals at the latest edge.
  Future<bool> retry() async {
    if (isClosed()) return false;
    final action = _failedAction;
    if (action != null) return action();
    final more = await timeline.retry();
    if (!isClosed() && !timeline.viewingHistory.value) {
      timeline.flushBuffered();
    }
    return more;
  }

  void invalidate() {
    _revision++;
    _failedAction = null;
    _latestRequest = null;
    positions.cancel();
    timeline.cancelWindowChange();
    seeking.value = false;
    returning.value = false;
    if (!isClosed() && !timeline.viewingHistory.value) {
      timeline.flushBuffered();
      updateScrollOffset(distanceFromLatest());
    }
  }
}
