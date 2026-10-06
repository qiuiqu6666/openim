import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'scrolling/chat_list_position_controller.dart';

export 'scrolling/chat_list_position_controller.dart'
    show ChatListPositionController;

typedef ChatViewportChanged = void Function(
    List<String> readIDs, double distanceFromLatest);

/// Keeps the original history on one side of a stable sliver center. Live
/// arrivals grow the other side without estimating their heights or moving
/// the history reader. Identity snapshots must follow the builder's order.
class ChatListViewport extends StatefulWidget {
  const ChatListViewport({
    super.key,
    required this.messageIDs,
    required this.itemCount,
    required this.itemBuilder,
    required this.padding,
    this.controller,
    this.physics,
    this.findChildIndexCallback,
    this.onViewportChanged,
    this.positionController,
  });

  final List<String> messageIDs;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsets padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final int? Function(Key)? findChildIndexCallback;
  final ChatViewportChanged? onViewportChanged;
  final ChatListPositionController? positionController;

  @override
  State<ChatListViewport> createState() => _ChatListViewportState();
}

class _ChatListViewportState extends State<ChatListViewport>
    with WidgetsBindingObserver {
  final _viewportKey = GlobalKey();
  Key _historyKey = UniqueKey();
  Key _newerKey = UniqueKey();
  final _ownedController = ScrollController();
  ScrollController get _controller => widget.controller ?? _ownedController;
  final _mountedRows = <String, _RenderChatRow>{};
  List<String> _ids = const [];
  String? _centerID;
  int _split = 0;
  bool _scheduled = false;
  bool _restoring = false;
  bool _foreground = true;
  Map<String, double> _lastAnchors = {};
  Map<String, double>? _restoreAnchors;
  int _restoreAttempts = 0;
  int _jumpGeneration = 0;
  bool _jumping = false;
  bool _disposing = false;
  String? _jumpTargetID;
  Completer<bool>? _pendingJump;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _updatePartition();
    _controller.addListener(_onScroll);
    widget.positionController
        ?.attach(this, _jumpToMessage, _cancelPositionJump);
  }

  @override
  void didUpdateWidget(covariant ChatListViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionController != widget.positionController) {
      oldWidget.positionController?.detach(this);
      widget.positionController
          ?.attach(this, _jumpToMessage, _cancelPositionJump);
    }
    if (_jumpTargetID != null && !widget.messageIDs.contains(_jumpTargetID)) {
      _cancelPositionJump();
    }
    if (oldWidget.controller != widget.controller) {
      _cancelPositionJump();
      (oldWidget.controller ?? _ownedController).removeListener(_onScroll);
      _controller.addListener(_onScroll);
      _restoreAnchors = null;
      _lastAnchors.clear();
      _centerID = null;
    } else if (!listEquals(_ids, widget.messageIDs)) {
      if (!_jumping &&
          _distance <= 1 &&
          (!_controller.hasClients ||
              !_controller.position.isScrollingNotifier.value)) {
        _useLatestCenter(widget.messageIDs);
      } else if (!_jumping && !_onlyAddsAtEdges(widget.messageIDs)) {
        // A stable center already preserves prepends and older pages. Restoring
        // their previous frame's coordinates would undo a concurrent drag.
        _restoreAnchors = Map.of(_lastAnchors);
        _restoreAttempts = 0;
      }
    }
    _updatePartition();
    _schedule();
  }

  bool _onlyAddsAtEdges(List<String> next) {
    if (_ids.isEmpty) return true;
    final start = next.indexOf(_ids.first);
    if (start < 0 || start + _ids.length > next.length) return false;
    for (var i = 0; i < _ids.length; i++) {
      if (_ids[i] != next[start + i]) return false;
    }
    return true;
  }

  void _useLatestCenter(List<String> ids) {
    final latest = ids.indexWhere((id) => id.isNotEmpty);
    final centerID = latest < 0 ? null : ids[latest];
    if (_centerID != centerID || _split > 0) {
      // The old sliver's layout offsets belong to the previous coordinate
      // origin; retaining them would cause a corrective jump into older rows.
      _historyKey = UniqueKey();
      _newerKey = UniqueKey();
    }
    _centerID = centerID;
    _restoreAnchors = null;
    _lastAnchors.clear();
    if (_controller.hasClients) {
      // This changes the coordinate origin, not the reader's position. Avoid a
      // second scroll notification with the old negative minimum extent.
      _controller.position.correctBy(-_controller.position.pixels);
    }
  }

  void _onScroll() {
    if (!_jumping &&
        _split > 0 &&
        _distance <= 1 &&
        !_controller.position.isScrollingNotifier.value) {
      // Returning to latest makes its first row the new center. Leaving the
      // newest row last in a before-center SliverList would walk every arrival
      // to find that row's variable-height position.
      setState(() {
        _useLatestCenter(_ids);
        _updatePartition();
      });
    }
    _schedule();
  }

  void _cancelPositionJump() {
    _jumpGeneration++;
    final wasJumping = _jumping;
    _jumping = false;
    _jumpTargetID = null;
    final pending = _pendingJump;
    _pendingJump = null;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    if (wasJumping) {
      _restoreAnchors = null;
      _lastAnchors.clear();
      if (mounted && !_disposing) {
        setState(() {});
        _schedule();
      }
    }
  }

  Future<bool> _jumpToMessage(String id, double alignment) {
    _cancelPositionJump();
    if (!mounted || !_ids.contains(id) || !_controller.hasClients) {
      return Future.value(false);
    }
    final generation = _jumpGeneration;
    final pending = _pendingJump = Completer<bool>();
    setState(() {
      _jumping = true;
      _jumpTargetID = id;
      _restoreAnchors = null;
      _lastAnchors.clear();
      // Moving the sliver center materializes the target directly, even with
      // thousands of variable-height messages between it and the old view.
      _centerID = id;
      _historyKey = UniqueKey();
      _newerKey = UniqueKey();
      _updatePartition();
      final position = _controller.position;
      position
          .jumpTo(position.pixels); // Cancel an outstanding scroll activity.
      position.correctBy(-position.pixels);
    });
    _positionMessage(id, alignment, generation).then((visible) {
      if (!mounted || generation != _jumpGeneration) return;
      setState(() {
        _jumping = false;
        _jumpTargetID = null;
        _pendingJump = null;
      });
      pending.complete(visible);
      _schedule();
    });
    return pending.future;
  }

  bool _isCurrentJump(String id, int generation) =>
      mounted && generation == _jumpGeneration && _ids.contains(id);

  Future<void> _nextPaint() {
    WidgetsBinding.instance.ensureVisualUpdate();
    return WidgetsBinding.instance.endOfFrame;
  }

  Future<bool> _positionMessage(
      String id, double alignment, int generation) async {
    for (var attempt = 0; attempt < 6; attempt++) {
      await _nextPaint();
      if (!_isCurrentJump(id, generation) || !_controller.hasClients) {
        return false;
      }
      final row = _mountedRows[id];
      if (row == null || !row.attached || !row.hasSize) continue;
      final viewportBefore = _viewportKey.currentContext?.findRenderObject();
      if (viewportBefore is! RenderBox ||
          !viewportBefore.attached ||
          !viewportBefore.hasSize) {
        continue;
      }
      final actualTop =
          row.localToGlobal(Offset.zero, ancestor: viewportBefore).dy;
      final desiredTop =
          (viewportBefore.size.height - row.size.height) * (1 - alignment);
      final position = _controller.position;
      // ensureVisible assumes the standard viewport origin. This viewport's
      // adaptive anchor moves a short history sliver toward the top, so use
      // its actual painted row coordinates instead (reverse: pixels move
      // rows down). At an edge, retain the nearest fully visible placement.
      final pixels = (position.pixels + desiredTop - actualTop)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((pixels - position.pixels).abs() > 0.5) {
        position.jumpTo(pixels);
      }
      await _nextPaint();
      if (!_isCurrentJump(id, generation)) return false;
      final viewport = _viewportKey.currentContext?.findRenderObject();
      final painted = _mountedRows[id];
      if (viewport is! RenderBox ||
          !viewport.attached ||
          !viewport.hasSize ||
          painted == null ||
          !painted.attached ||
          !painted.hasSize) {
        continue;
      }
      final top = painted.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final bottom = top + painted.size.height;
      if (bottom > 0 &&
          top < viewport.size.height &&
          (painted.size.height > viewport.size.height ||
              top >= -0.5 && bottom <= viewport.size.height + 0.5)) {
        return true;
      }
    }
    return false;
  }

  void _updatePartition() {
    final next = List<String>.of(widget.messageIDs);
    final oldCenter = _centerID;
    var index = oldCenter == null ? -1 : next.indexOf(oldCenter);
    if (index < 0 && oldCenter != null) {
      // A deleted center chooses its nearest surviving history neighbour.
      final nextIndices = <String, int>{
        for (var i = 0; i < next.length; i++)
          if (next[i].isNotEmpty) next[i]: i,
      };
      for (final id in _ids.skip(_split)) {
        if (id.isEmpty) continue;
        index = nextIndices[id] ?? -1;
        if (index >= 0) break;
      }
    }
    if (index < 0) index = next.indexWhere((id) => id.isNotEmpty);
    _split = index < 0 ? 0 : index;
    _centerID = index < 0 ? null : next[index];
    _ids = next;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _schedule();
  }

  @override
  void dispose() {
    _disposing = true;
    widget.positionController?.detach(this);
    _cancelPositionJump();
    _controller.removeListener(_onScroll);
    _ownedController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _mountedRows.clear();
    super.dispose();
  }

  double get _distance {
    final controller = _controller;
    if (!controller.hasClients || !controller.position.hasContentDimensions) {
      return 0;
    }
    return math.max(
        0, controller.position.pixels - controller.position.minScrollExtent);
  }

  void _schedule() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _measure();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _rowAttached(_RenderChatRow row) => _mountedRows[row.id] = row;
  void _rowDetached(_RenderChatRow row) {
    if (identical(_mountedRows[row.id], row)) _mountedRows.remove(row.id);
  }

  void _rowLayout(bool resized) {
    if (resized &&
        !_jumping &&
        !_restoring &&
        _restoreAnchors == null &&
        _distance > 1) {
      _restoreAnchors = Map.of(_lastAnchors);
      _restoreAttempts = 0;
    }
    _schedule();
  }

  void _measure() {
    if (_jumping ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox ||
        !viewport.attached ||
        !viewport.hasSize ||
        viewport.size.height <= 0) {
      return;
    }
    final controller = _controller;
    final anchors = <String, double>{};
    final read = <String>[];
    final candidates = _mountedRows.values.toList(growable: false);
    for (final row in candidates) {
      if (!row.attached || !row.hasSize || row.size.height <= 0) continue;
      final top = row.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final bottom = top + row.size.height;
      if (bottom > 0 && top < viewport.size.height) anchors[row.id] = top;
      if (bottom > 0 &&
          bottom <= viewport.size.height + 0.5 &&
          (top >= -0.5 || row.size.height > viewport.size.height)) {
        read.add(row.id);
      }
    }
    final restore = _restoreAnchors;
    if (restore != null && controller.hasClients) {
      for (final entry in restore.entries) {
        final actual = anchors[entry.key];
        if (actual == null) continue;
        final delta =
            entry.value - actual; // reverse list: pixels move rows down.
        if (delta.abs() > 0.5 && _restoreAttempts++ < 3) {
          _restoring = true;
          final position = controller.position;
          controller.jumpTo((position.pixels + delta)
              .clamp(position.minScrollExtent, position.maxScrollExtent));
          _restoring = false;
          _schedule();
          return; // Confirm reading only after corrected layout has painted.
        }
        break;
      }
      _restoreAnchors = null;
    }
    _lastAnchors = anchors;
    widget.onViewportChanged?.call(read, _distance);
  }

  Widget _row(BuildContext context, int index) {
    final child = widget.itemBuilder(context, index);
    final id = index < _ids.length ? _ids[index] : '';
    if (id.isEmpty) return child;
    return _ChatRow(
      key: child.key,
      id: id,
      onAttach: _rowAttached,
      onDetach: _rowDetached,
      onLayout: _rowLayout,
      child: child,
    );
  }

  int? _childIndex(Key key, bool newer) {
    final index = widget.findChildIndexCallback?.call(key);
    if (index == null) return null;
    if (newer) return index < _split ? _split - index - 1 : null;
    return index >= _split ? index - _split : null;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _schedule();
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification && !_restoring) {
              final delta = notification.scrollDelta ?? 0;
              if (delta != 0) {
                _lastAnchors =
                    _lastAnchors.map((id, top) => MapEntry(id, top + delta));
              }
              if (notification.dragDetails != null) {
                _cancelPositionJump();
                _restoreAnchors = null;
              }
            }
            _schedule();
            return false;
          },
          child: ClipRect(
            key: _viewportKey,
            child: _ChatCenteredScrollView(
              controller: _controller,
              physics: widget.physics,
              center: _historyKey,
              positioning: _jumping,
              slivers: [
                SliverList(
                    key: _newerKey,
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _row(context, _split - index - 1),
                      childCount: _split,
                      findChildIndexCallback: (key) => _childIndex(key, true),
                    )),
                SliverPadding(
                  key: _historyKey,
                  padding: widget.padding,
                  sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                    (context, index) => _row(context, _split + index),
                    childCount: widget.itemCount - _split,
                    findChildIndexCallback: (key) => _childIndex(key, false),
                  )),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ChatRow extends SingleChildRenderObjectWidget {
  const _ChatRow(
      {super.key,
      required this.id,
      required this.onAttach,
      required this.onDetach,
      required this.onLayout,
      required super.child});
  final String id;
  final ValueChanged<_RenderChatRow> onAttach;
  final ValueChanged<_RenderChatRow> onDetach;
  final ValueChanged<bool> onLayout;
  @override
  _RenderChatRow createRenderObject(BuildContext context) =>
      _RenderChatRow(id, onAttach, onDetach, onLayout);
  @override
  void updateRenderObject(BuildContext context, _RenderChatRow renderObject) {
    if (renderObject.id != id && renderObject.attached) {
      renderObject.onDetach(renderObject);
    }
    renderObject
      ..id = id
      ..onAttach = onAttach
      ..onDetach = onDetach
      ..onLayout = onLayout;
    if (renderObject.attached) onAttach(renderObject);
  }
}

class _RenderChatRow extends RenderProxyBox {
  _RenderChatRow(this.id, this.onAttach, this.onDetach, this.onLayout);
  String id;
  ValueChanged<_RenderChatRow> onAttach;
  ValueChanged<_RenderChatRow> onDetach;
  ValueChanged<bool> onLayout;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    onAttach(this);
  }

  @override
  void detach() {
    onDetach(this);
    super.detach();
  }

  @override
  void performLayout() {
    final oldHeight = hasSize ? size.height : null;
    super.performLayout();
    onLayout(oldHeight != null && (oldHeight - size.height).abs() > 0.5);
  }
}

class _ChatCenteredScrollView extends CustomScrollView {
  const _ChatCenteredScrollView(
      {super.controller,
      super.physics,
      this.positioning = false,
      required super.center,
      required super.slivers})
      : super(reverse: true);
  final bool positioning;
  @override
  Widget buildViewport(BuildContext context, ViewportOffset offset,
          AxisDirection axisDirection, List<Widget> slivers) =>
      _ChatTopAlignedViewport(
        axisDirection: axisDirection,
        offset: offset,
        center: center,
        positioning: positioning,
        cacheExtent: cacheExtent,
        slivers: slivers,
      );
}

/// A center viewport cannot shrink-wrap. Its history sliver's measured extent
/// instead places short conversations at the top during the same layout pass.
class _ChatTopAlignedViewport extends Viewport {
  _ChatTopAlignedViewport(
      {required super.axisDirection,
      required super.offset,
      required super.center,
      required this.positioning,
      super.cacheExtent,
      required super.slivers});
  final bool positioning;
  @override
  RenderViewport createRenderObject(BuildContext context) =>
      _RenderChatViewport(
        axisDirection: axisDirection,
        crossAxisDirection:
            Viewport.getDefaultCrossAxisDirection(context, axisDirection),
        offset: offset,
        positioning: positioning,
        cacheExtent: cacheExtent,
      );
  @override
  void updateRenderObject(
      BuildContext context, covariant _RenderChatViewport renderObject) {
    renderObject
      ..axisDirection = axisDirection
      ..crossAxisDirection =
          Viewport.getDefaultCrossAxisDirection(context, axisDirection)
      ..offset = offset
      ..positioning = positioning
      ..cacheExtent = cacheExtent;
  }
}

class _RenderChatViewport extends RenderViewport {
  _RenderChatViewport(
      {required super.axisDirection,
      required super.crossAxisDirection,
      required super.offset,
      required this.positioning,
      super.cacheExtent});
  bool positioning;
  double? _lastCenterPaint;
  RenderSliver? _lastCenter;
  double _adaptiveAnchor = 0;
  @override
  double get anchor => _adaptiveAnchor;
  @override
  void performLayout() {
    if (!identical(center, _lastCenter)) {
      _lastCenterPaint = null;
      _lastCenter = center;
    }
    final position = offset is ScrollPosition ? offset as ScrollPosition : null;
    final pinned = !positioning &&
        (position == null ||
            !position.hasContentDimensions ||
            (!position.isScrollingNotifier.value &&
                (position.pixels - position.minScrollExtent).abs() <= 1));
    super.performLayout();
    final height = size.height;
    final historyExtent = center?.geometry?.scrollExtent ?? height;
    final nextAnchor =
        height > 0 ? (1 - historyExtent / height).clamp(0.0, 1.0) : 0.0;
    final centerPaint = height * (1 - nextAnchor);
    if (_lastCenterPaint != null && !pinned) {
      final correction = _lastCenterPaint! - centerPaint;
      if (correction.abs() > 0.5) offset.correctBy(correction);
    }
    final changed = (anchor - nextAnchor).abs() > 0.00001;
    _adaptiveAnchor = nextAnchor;
    if (changed ||
        (_lastCenterPaint != null &&
            !pinned &&
            (_lastCenterPaint! - centerPaint).abs() > 0.5)) {
      super.performLayout();
    }
    _lastCenterPaint = centerPaint;
    // A jump to an estimated newest extent may materialize variable-height
    // arrivals and refine the edge. Finish at the actual edge, within layout.
    if (pinned && position != null) {
      for (var attempt = 0; attempt < 8; attempt++) {
        final correction = position.minScrollExtent - position.pixels;
        if (correction.abs() <= 0.5) break;
        offset.correctBy(correction);
        super.performLayout();
      }
    }
  }
}
