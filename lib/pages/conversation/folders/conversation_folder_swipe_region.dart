// Adapted from 99chat's conversation_folder_swipe_region.dart (d7c3c65).
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: relocated to the OpenIM conversation folders module.
import 'package:flutter/material.dart';

const double kConversationFolderSwipeMinDistance = 260;

int conversationFolderSwipeDirection({
  required double deltaX,
  required double deltaY,
  required double viewportWidth,
}) {
  final horizontal = deltaX.abs();
  final vertical = deltaY.abs();
  if (horizontal <= vertical * 1.35) return 0;

  final widthThreshold =
      (viewportWidth * 0.72).clamp(kConversationFolderSwipeMinDistance, 560);
  if (horizontal < widthThreshold) return 0;
  return deltaX < 0 ? 1 : -1;
}

({bool changed, String? folderId}) conversationFolderAfterSwipe({
  required List<String> folderIds,
  required String? selectedFolderId,
  required int direction,
}) {
  if (direction == 0 || folderIds.isEmpty) {
    return (changed: false, folderId: selectedFolderId);
  }
  final selectedIndex =
      selectedFolderId == null ? 0 : folderIds.indexOf(selectedFolderId) + 1;
  final currentIndex = selectedIndex <= 0 ? 0 : selectedIndex;
  final targetIndex =
      (currentIndex + direction).clamp(0, folderIds.length).toInt();
  if (targetIndex == currentIndex) {
    return (changed: false, folderId: selectedFolderId);
  }
  return (
    changed: true,
    folderId: targetIndex == 0 ? null : folderIds[targetIndex - 1],
  );
}

class ConversationFolderSwipeRegion extends StatefulWidget {
  const ConversationFolderSwipeRegion({
    super.key,
    required this.enabled,
    required this.onSwipe,
    required this.child,
  });

  final bool enabled;
  final ValueChanged<int> onSwipe;
  final Widget child;

  @override
  State<ConversationFolderSwipeRegion> createState() =>
      _ConversationFolderSwipeRegionState();
}

class _ConversationFolderSwipeRegionState
    extends State<ConversationFolderSwipeRegion> {
  int? _pointer;
  Offset? _start;

  void _reset() {
    _pointer = null;
    _start = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    _start = event.position;
  }

  void _onPointerUp(PointerUpEvent event, double viewportWidth) {
    if (event.pointer != _pointer) return;
    final start = _start;
    _reset();
    if (!widget.enabled || start == null) return;
    final delta = event.position - start;
    final direction = conversationFolderSwipeDirection(
      deltaX: delta.dx,
      deltaY: delta.dy,
      viewportWidth: viewportWidth,
    );
    if (direction != 0) widget.onSwipe(direction);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerCancel: (_) => _reset(),
          onPointerUp: (event) => _onPointerUp(event, constraints.maxWidth),
          child: widget.child,
        );
      },
    );
  }
}
