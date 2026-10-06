import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays out the full bubble while gradually reserving its row's extent.
/// The bubble starts below the enclosing chat viewport, which owns clipping;
/// no row-local clip cuts the bubble into a growing slice.
class ChatMessageArrivalViewportSlide extends SingleChildRenderObjectWidget {
  const ChatMessageArrivalViewportSlide({
    super.key,
    required this.messageID,
    required this.geometry,
    required this.progress,
    required this.extent,
    required this.outsideGap,
    required super.child,
  });

  final String messageID;
  final ChatMessageArrivalGeometry geometry;
  final double progress;
  final double extent;
  final double outsideGap;

  @override
  RenderChatMessageArrivalViewportSlide createRenderObject(
          BuildContext context) =>
      RenderChatMessageArrivalViewportSlide(
          messageID: messageID,
          geometry: geometry,
          progress: progress,
          extent: extent,
          outsideGap: outsideGap);

  @override
  void updateRenderObject(BuildContext context,
      RenderChatMessageArrivalViewportSlide renderObject) {
    renderObject
      ..geometry = geometry
      ..messageID = messageID
      ..progress = progress
      ..extent = extent
      ..outsideGap = outsideGap;
  }
}

/// Read-only adjacency between active, attached entrance rows in SDK order.
/// No message, viewport position or layout constraint is changed by a lookup.
class ChatMessageArrivalGeometry {
  final _indices = <String, int>{};
  final _movingIDs = <String>{};
  final _rows = <String, RenderChatMessageArrivalViewportSlide>{};
  bool _closed = false;

  void sync(Set<String> newestFirst, Set<String> movingIDs) {
    if (_closed) return;
    _indices
      ..clear()
      ..addEntries(
          newestFirst.indexed.map((entry) => MapEntry(entry.$2, entry.$1)));
    _movingIDs
      ..clear()
      ..addAll(movingIDs.where(_indices.containsKey));
    _rows.removeWhere((id, _) => !_movingIDs.contains(id));
    _invalidatePaint();
  }

  bool _isMoving(String id) => !_closed && _movingIDs.contains(id);

  void _attach(RenderChatMessageArrivalViewportSlide row) {
    if (_isMoving(row.messageID)) {
      _rows[row.messageID] = row;
      _invalidatePaint();
    }
  }

  void _detach(String id, RenderChatMessageArrivalViewportSlide row) {
    if (identical(_rows[id], row)) {
      _rows.remove(id);
      _invalidatePaint();
    }
  }

  void _invalidatePaint({String? olderID}) {
    final olderIndex = olderID == null ? null : _indices[olderID];
    for (final row in _rows.values) {
      if (!row.attached) continue;
      final index = _indices[row.messageID];
      if (olderIndex != null && index != null && index >= olderIndex) continue;
      // Sliver rows own repaint boundaries. A completed younger controller may
      // no longer tick while an older row still changes its painted position.
      row.markNeedsPaint();
      row.markNeedsSemanticsUpdate();
    }
  }

  RenderChatMessageArrivalViewportSlide? _olderRow(
      RenderChatMessageArrivalViewportSlide row, RenderBox viewport) {
    final index = _indices[row.messageID];
    if (_closed || index == null) return null;
    RenderChatMessageArrivalViewportSlide? nearest;
    int? nearestIndex;
    for (final candidate in _rows.values) {
      final candidateIndex = _indices[candidate.messageID];
      if (candidateIndex == null ||
          candidateIndex <= index ||
          (nearestIndex != null && candidateIndex >= nearestIndex) ||
          !candidate.attached ||
          !candidate.hasSize ||
          candidate.child?.hasSize != true ||
          !identical(
              RenderAbstractViewport.maybeOf(candidate.parent), viewport)) {
        continue;
      }
      nearest = candidate;
      nearestIndex = candidateIndex;
    }
    // Every edge points to a strictly larger SDK index, so recursive paint
    // lookup cannot cycle. At most the sixteen active entrances are retained.
    return nearest;
  }

  bool isSettled(String id) {
    final row = _rows[id];
    // An unmounted/offscreen row cannot be reported visible by the viewport.
    return row == null ||
        (row.progress >= 1 &&
            row.extent >= 1 &&
            row.paintOffset.dy.abs() <= .01);
  }

  void dispose() {
    _closed = true;
    _rows.clear();
    _movingIDs.clear();
    _indices.clear();
  }
}

class RenderChatMessageArrivalViewportSlide extends RenderProxyBox {
  RenderChatMessageArrivalViewportSlide({
    required String messageID,
    required ChatMessageArrivalGeometry geometry,
    required double progress,
    required double extent,
    required double outsideGap,
  })  : _messageID = messageID,
        _geometry = geometry,
        _progress = progress,
        _extent = extent,
        _outsideGap = outsideGap;

  String _messageID;
  String get messageID => _messageID;
  set messageID(String value) {
    if (_messageID == value) return;
    _geometry._detach(_messageID, this);
    _messageID = value;
    if (attached) _geometry._attach(this);
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  ChatMessageArrivalGeometry _geometry;
  set geometry(ChatMessageArrivalGeometry value) {
    if (identical(_geometry, value)) return;
    _geometry._detach(_messageID, this);
    _geometry = value;
    if (attached) _geometry._attach(this);
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _geometry._attach(this);
  }

  @override
  void detach() {
    _geometry._detach(_messageID, this);
    super.detach();
  }

  @override
  void dispose() {
    _geometry._detach(_messageID, this);
    super.dispose();
  }

  double _progress;
  double get progress => _progress;
  set progress(double value) {
    if (_progress == value) return;
    _progress = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
    _geometry._invalidatePaint(olderID: _messageID);
  }

  double _extent;
  double get extent => _extent;
  set extent(double value) {
    if (_extent == value) return;
    _extent = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
    _geometry._invalidatePaint(olderID: _messageID);
  }

  double _outsideGap;
  double get outsideGap => _outsideGap;
  set outsideGap(double value) {
    if (_outsideGap == value) return;
    _outsideGap = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
    _geometry._invalidatePaint(olderID: _messageID);
  }

  /// Always derive the offset from this frame's layout. In particular, a
  /// zero-height first row has not painted yet but localToGlobal/getRect still
  /// need to report its bubble below the viewport, rather than at its row slot.
  Offset get paintOffset {
    if (!attached || !hasSize || !_geometry._isMoving(_messageID)) {
      return Offset.zero;
    }
    final viewport = RenderAbstractViewport.maybeOf(parent);
    if (viewport is! RenderBox) return Offset.zero;
    final viewportBox = viewport as RenderBox;
    if (!viewportBox.hasSize) return Offset.zero;
    final rowTop = localToGlobal(Offset.zero, ancestor: viewportBox).dy;
    final distance =
        math.max(0.0, viewportBox.size.height + _outsideGap - rowTop);
    var paintedTop = rowTop + distance * (1 - _progress);
    final older = _geometry._olderRow(this, viewportBox);
    if (older != null) {
      final olderTop =
          older.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
      final olderBottom =
          olderTop + older.paintOffset.dy + older.child!.size.height;
      paintedTop = math.max(paintedTop, olderBottom);
    }
    return Offset(0, paintedTop - rowTop);
  }

  Size _reservedSize(Size fullSize, BoxConstraints constraints) =>
      constraints.constrain(Size(fullSize.width, fullSize.height * _extent));

  @override
  void performLayout() {
    final bubble = child;
    if (bubble == null) {
      size = constraints.smallest;
      return;
    }
    // Use the original constraints so text/media retain their final dimensions.
    bubble.layout(constraints, parentUsesSize: true);
    size = _reservedSize(bubble.size, constraints);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final fullSize = child?.getDryLayout(constraints) ?? constraints.smallest;
    return _reservedSize(fullSize, constraints);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final bubble = child;
    if (bubble != null) context.paintChild(bubble, offset + paintOffset);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = paintOffset;
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final bubble = child;
    return bubble != null &&
        result.addWithPaintOffset(
          offset: paintOffset,
          position: position,
          hitTest: (result, position) =>
              bubble.hitTest(result, position: position),
        );
  }
}
