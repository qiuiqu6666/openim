import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'message_selection_controller.dart';
import 'message_selection_drag_tokens.dart';
import 'message_selection_layout.dart';

/// Long-press range selection over the existing lazy chat list. Regular drags
/// remain owned by its Scrollable; the accepted long press owns only this stroke.
class MessageSelectionDragRegion extends StatefulWidget {
  const MessageSelectionDragRegion({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.child,
  });
  final MessageSelectionController controller;
  final ScrollController scrollController;
  final Widget child;

  @override
  State<MessageSelectionDragRegion> createState() =>
      _MessageSelectionDragRegionState();
}

class _MessageSelectionDragRegionState extends State<MessageSelectionDragRegion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _regionKey = GlobalKey();
  late final Ticker _ticker;
  Duration _previousTick = Duration.zero;
  String? _anchorID;
  Set<String> _baseline = {};
  bool _selecting = false;
  Offset? _pointer;
  bool _paintPending = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller.addListener(_onSelectionChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(MessageSelectionDragRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.scrollController != widget.scrollController) {
      _finish();
      oldWidget.controller.removeListener(_onSelectionChanged);
      widget.controller.addListener(_onSelectionChanged);
    }
  }

  void _onSelectionChanged() {
    if (!widget.controller.canInteract ||
        (_anchorID != null &&
            !widget.controller.containsSelectableID(_anchorID!))) {
      _finish();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _finish();
  }

  @override
  void deactivate() {
    _finish();
    super.deactivate();
  }

  @override
  void dispose() {
    _finish();
    widget.controller.removeListener(_onSelectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  RenderBox? get _region {
    final render = _regionKey.currentContext?.findRenderObject();
    return render is RenderBox && render.attached && render.hasSize
        ? render
        : null;
  }

  List<RenderMessageSelectionLayout> _rows(RenderBox region, Rect viewport) {
    final rows = <RenderMessageSelectionLayout>[];
    void visit(RenderObject render) {
      if (render is RenderMessageSelectionLayout) {
        if (render.attached &&
            render.hasSize &&
            render.selecting &&
            render.globalRowBounds.overlaps(viewport)) {
          rows.add(render);
        }
        return;
      }
      render.visitChildren(visit);
    }

    region.visitChildren(visit);
    rows.sort((a, b) => a.globalRowBounds.top.compareTo(b.globalRowBounds.top));
    return rows;
  }

  void _start(LongPressStartDetails details) {
    if (!widget.controller.canInteract ||
        ModalRoute.isCurrentOf(context) == false) {
      return;
    }
    final region = _region;
    if (region == null) return;
    final viewport = region.localToGlobal(Offset.zero) & region.size;
    if (!viewport.contains(details.globalPosition)) return;
    final rows = _rows(region, viewport);
    RenderMessageSelectionLayout? origin;
    for (final row in rows) {
      if (row.globalRowBounds.contains(details.globalPosition)) {
        origin = row;
        break;
      }
    }
    if (origin == null) return;
    _anchorID = origin.messageID;
    _baseline = widget.controller.selectedIDs;
    _selecting = !_baseline.contains(_anchorID);
    _pointer = details.globalPosition;
    // Stop an existing fling only after the long press wins its gesture arena.
    if (widget.scrollController.hasClients) {
      final position = widget.scrollController.position;
      position.jumpTo(position.pixels);
    }
    _paintRange();
    _syncTicker();
  }

  void _move(LongPressMoveUpdateDetails details) {
    if (_anchorID == null || !widget.controller.canInteract) return;
    _pointer = details.globalPosition;
    _paintRange();
    _syncTicker();
  }

  void _paintRange() {
    final anchorID = _anchorID;
    final pointer = _pointer;
    final region = _region;
    if (anchorID == null ||
        pointer == null ||
        region == null ||
        !widget.controller.canInteract ||
        ModalRoute.isCurrentOf(context) == false) {
      return;
    }
    final viewport = region.localToGlobal(Offset.zero) & region.size;
    if (pointer.dx < viewport.left || pointer.dx > viewport.right) return;
    final rows = _rows(region, viewport);
    if (rows.isEmpty) return;
    final y = pointer.dy.clamp(viewport.top, viewport.bottom);
    // In a timeline gap or over a notification, retain the nearest selectable
    // row. No system notice itself becomes selected.
    final endpoint = rows.reduce((a, b) {
      double distance(RenderMessageSelectionLayout row) {
        final bounds = row.globalRowBounds;
        return y < bounds.top
            ? bounds.top - y
            : y > bounds.bottom
                ? y - bounds.bottom
                : 0;
      }

      return distance(a) <= distance(b) ? a : b;
    });
    widget.controller.updateDragRange(anchorID, endpoint.messageID,
        baseline: _baseline, selected: _selecting);
  }

  double _edgeVelocity() {
    final region = _region;
    final pointer = _pointer;
    if (region == null ||
        pointer == null ||
        !widget.scrollController.hasClients) {
      return 0;
    }
    final viewport = region.localToGlobal(Offset.zero) & region.size;
    if (pointer.dx < viewport.left || pointer.dx > viewport.right) return 0;
    final edge = MessageSelectionDragTokens.edgeZone;
    double depth;
    double direction;
    if (pointer.dy < viewport.top + edge) {
      depth = (viewport.top + edge - pointer.dy) / edge;
      direction = -1;
    } else if (pointer.dy > viewport.bottom - edge) {
      depth = (pointer.dy - viewport.bottom + edge) / edge;
      direction = 1;
    } else {
      return 0;
    }
    final speed = MessageSelectionDragTokens.minSpeed +
        (MessageSelectionDragTokens.maxSpeed -
                MessageSelectionDragTokens.minSpeed) *
            depth.clamp(0, 1);
    final axis = widget.scrollController.position.axisDirection;
    // OpenIM's centered chat viewport is reversed and can have negative pixels.
    if (axis == AxisDirection.up || axis == AxisDirection.left) direction *= -1;
    return speed * direction;
  }

  void _syncTicker() {
    if (_anchorID != null &&
        widget.controller.canInteract &&
        _edgeVelocity() != 0) {
      if (!_ticker.isActive) {
        _previousTick = Duration.zero;
        _ticker.start();
      }
    } else {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (_anchorID == null ||
        !mounted ||
        !widget.controller.canInteract ||
        ModalRoute.isCurrentOf(context) == false ||
        !widget.scrollController.hasClients) {
      _finish();
      return;
    }
    final velocity = _edgeVelocity();
    if (velocity == 0) {
      _ticker.stop();
      return;
    }
    final seconds = ((elapsed - _previousTick).inMicroseconds / 1000000)
        .clamp(0, MessageSelectionDragTokens.maxFrameSeconds);
    _previousTick = elapsed;
    final position = widget.scrollController.position;
    if (!position.hasContentDimensions) return;
    final next = (position.pixels + velocity * seconds)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (next != position.pixels) position.jumpTo(next);
    // Scroll layout must settle before consulting lazy row geometry again.
    if (!_paintPending) {
      _paintPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _paintPending = false;
        if (mounted) _paintRange();
      });
    }
  }

  void _finish() {
    _ticker.stop();
    _anchorID = null;
    _pointer = null;
    _baseline = {};
  }

  @override
  Widget build(BuildContext context) {
    if (ModalRoute.isCurrentOf(context) == false) _finish();
    return ListenableBuilder(
      listenable: widget.controller,
      child: widget.child,
      builder: (context, child) => GestureDetector(
        key: const ValueKey('message-selection-drag-region'),
        behavior: HitTestBehavior.opaque,
        onLongPressStart: widget.controller.canInteract ? _start : null,
        onLongPressMoveUpdate: widget.controller.canInteract ? _move : null,
        onLongPressEnd: widget.controller.canInteract ? (_) => _finish() : null,
        onLongPressCancel: widget.controller.canInteract ? _finish : null,
        child: SizedBox(key: _regionKey, child: child),
      ),
    );
  }
}
