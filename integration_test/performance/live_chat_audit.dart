import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/messages/loading/chat_initial_window_transition.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_tile.dart';

/// Test-only observation of the actual mounted timeline. No message contents,
/// account IDs, conversation IDs or message IDs leave this object.
class LiveChatAudit {
  LiveChatAudit(this.logic, this.root);
  final ChatLogic logic;
  final Element root;
  final _previousOrder = <String>[];
  Map<String, Rect> _previousRects = {};
  final _elements = <String, Element>{};
  double? _previousOffset;
  int? _previousCount;
  double? _previousHeight;
  bool _previousArriving = false;
  final shifts = <Map<String, Object?>>[];
  int frames = 0, orderErrors = 0, duplicateErrors = 0, foreignRows = 0;
  int relativeOrderChanges = 0, identityChanges = 0, prematureRows = 0;
  int maxSequenceRegression = 0, maxSeq = 0, maxRows = 0;
  int? firstVisibleMaxSeq, firstVisibleMinSeq;
  double maxUnexplainedShift = 0;
  int observationUs = 0;
  bool enabled = true;

  bool belongs(Message m) => logic.isSingleChat
      ? (m.sendID == logic.userID || m.recvID == logic.userID)
      : m.groupID == logic.groupID;

  void sample() {
    if (!enabled || !root.mounted || logic.isClosed) return;
    final watch = Stopwatch()..start();
    final route = ModalRoute.of(root);
    if (route?.isCurrent == false) return;
    final rootBox = root.findRenderObject();
    if (rootBox is! RenderBox || !rootBox.hasSize) return;
    ChatInitialWindowTransitionState? reveal;
    double? contentOpacity;
    final tiles = <Element>[];
    void visit(Element e) {
      if (e is StatefulElement && e.state is ChatInitialWindowTransitionState) {
        reveal = e.state as ChatInitialWindowTransitionState;
      }
      if (reveal != null && e.widget is FadeTransition) {
        contentOpacity ??= (e.widget as FadeTransition).opacity.value;
      }
      if (e.widget is ChatMessageTile) {
        tiles.add(e);
      } else {
        e.visitChildren(visit);
      }
    }

    root.visitChildren(visit);
    // During a zero-opacity skeleton the mounted backing list is not visible.
    if (reveal == null || (contentOpacity ?? 0) <= 0) {
      observationUs += watch.elapsedMicroseconds;
      return;
    }
    frames++;
    if (!logic.initialWindowReady.value && tiles.isNotEmpty) prematureRows++;
    final rows = logic.messageList;
    maxRows = math.max(maxRows, rows.length);
    final ids = rows.map((m) => m.clientMsgID ?? '').toList();
    if (ids.toSet().length != ids.length) duplicateErrors++;
    var previousSeq = 0;
    var currentMax = 0;
    for (final m in rows) {
      if (!belongs(m)) foreignRows++;
      final seq = m.seq ?? 0;
      if (seq <= 0) continue;
      if (seq < previousSeq) orderErrors++;
      previousSeq = seq;
      currentMax = math.max(currentMax, seq);
    }
    if (currentMax > 0 && currentMax < maxSeq) maxSequenceRegression++;
    maxSeq = math.max(maxSeq, currentMax);
    final oldSet = _previousOrder.toSet();
    final newSet = ids.toSet();
    final oldCommon = _previousOrder.where(newSet.contains).toList();
    final newCommon = ids.where(oldSet.contains).toList();
    if (oldCommon.join('|') != newCommon.join('|')) relativeOrderChanges++;
    _previousOrder
      ..clear()
      ..addAll(ids);
    final rects = <String, Rect>{};
    final sequences = <int>[];
    final screenTop = rootBox.localToGlobal(Offset.zero).dy;
    for (final e in tiles) {
      final message = (e.widget as ChatMessageTile).message;
      final id = message.clientMsgID;
      final box = e.findRenderObject();
      if (id == null || box is! RenderBox || !box.hasSize) continue;
      final p = box.localToGlobal(Offset.zero, ancestor: rootBox);
      final rect = p & box.size;
      if (rect.bottom <= 0 || rect.top >= rootBox.size.height) continue;
      // A header can move the viewport's origin while a reverse list keeps
      // messages at the same SCREEN position. Compare screen Y, not local Y.
      rects[id] = rect.shift(Offset(0, screenTop));
      if ((message.seq ?? 0) > 0) sequences.add(message.seq!);
      if (_previousRects.containsKey(id) && _elements[id] != e) {
        identityChanges++;
      }
      _elements[id] = e;
    }
    if (sequences.isNotEmpty) {
      firstVisibleMinSeq ??= sequences.reduce(math.min);
      firstVisibleMaxSeq ??= sequences.reduce(math.max);
    }
    final offset =
        logic.scrollController.hasClients ? logic.scrollController.offset : 0.0;
    // Ignore deliberate scrolling and normal new-message insertion. Stable
    // rows with unchanged list/offset must not move as images finish loading.
    if (_previousCount == rows.length &&
        _previousOffset != null &&
        (offset - _previousOffset!).abs() < .1 &&
        !logic.messageArrivals.hasEntering &&
        !_previousArriving) {
      for (final entry in rects.entries) {
        final old = _previousRects[entry.key];
        if (old == null || logic.messageArrivals.isEntering(entry.key)) {
          continue;
        }
        maxUnexplainedShift = math.max(
            maxUnexplainedShift,
            math.max((entry.value.top - old.top).abs(),
                (entry.value.height - old.height).abs()));
        if (shifts.length < 12 &&
            ((entry.value.top - old.top).abs() > 1 ||
                (entry.value.height - old.height).abs() > 1)) {
          shifts.add({
            'topDelta': entry.value.top - old.top,
            'heightDelta': entry.value.height - old.height,
            'viewportHeight': rootBox.size.height,
            'previousViewportHeight': _previousHeight,
            'rows': rows.length,
            'maxSeq': currentMax,
            'announcementVisible': logic.announcement.value.isNotEmpty
          });
        }
      }
    }
    _previousRects = rects;
    _elements.removeWhere((id, _) => !rects.containsKey(id));
    _previousOffset = offset;
    _previousCount = rows.length;
    _previousHeight = rootBox.size.height;
    _previousArriving = logic.messageArrivals.hasEntering;
    observationUs += watch.elapsedMicroseconds;
  }

  Map<String, Object?> report() => {
        'paintSamples': frames,
        'orderErrors': orderErrors,
        'duplicateErrors': duplicateErrors,
        'foreignRows': foreignRows,
        'relativeOrderChanges': relativeOrderChanges,
        'identityChanges': identityChanges,
        'prematureRows': prematureRows,
        'maxSequenceRegression': maxSequenceRegression,
        'firstVisibleMinSeq': firstVisibleMinSeq,
        'firstVisibleMaxSeq': firstVisibleMaxSeq,
        'maxSeq': maxSeq,
        'maxRows': maxRows,
        'maxUnexplainedShiftPx': maxUnexplainedShift,
        'observerTotalMs': observationUs / 1000,
        'shifts': shifts,
      };
}
