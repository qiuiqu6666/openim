// Adapted from 99chat's conversation_folder_chip_bar.dart (d7c3c65).
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: use OpenIM ChatFolder and caller-owned order/data operations.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../conversation_organizer.dart';

class _FolderBarTokens {
  static const selectedLight = Color(0xFFECECEC);
  static const quietBadgeLight = Color(0xFFA8A8AE);
  static const addLight = Color(0xFF8E8E93);
  static const unread = Color(0xFFFF524B);
  static const shadow = Color(0xFF000000);
  static const shadowOpacity = .06;
  static const dragShadow = Color(0x42000000);
  static const height = 32.0;
  static const labelSize = AppTokens.captionFontSize;
  static const labelHeight = 1.1;
  static const addSize = 21.0;
  static const badgeSize = 16.0;
  static const badgeFontSize = 10.0;
  static const closeSize = 14.0;
}

/// The conversation folder capsules; mount only when folders exist.
///
/// Folder order remains owned by the parent. Reordering is available only when
/// the parent supplies a callback and confirms the resulting order in folders.
class ConversationFolderBar extends StatefulWidget {
  const ConversationFolderBar({
    super.key,
    required this.folders,
    required this.selectedFolderID,
    required this.unreadForFolder,
    required this.hasNotifiableUnreadForFolder,
    required this.onSelectAll,
    required this.onSelectFolder,
    required this.onCreateFolder,
    required this.onFolderLongPress,
    this.reorderEditing = false,
    this.onExitReorderEditing,
    this.onDeleteFolder,
    this.onReorderFolders,
  });

  final List<ChatFolder> folders;
  final String? selectedFolderID;
  final int Function(ChatFolder) unreadForFolder;
  final bool Function(ChatFolder) hasNotifiableUnreadForFolder;
  final VoidCallback onSelectAll;
  final ValueChanged<String> onSelectFolder;
  final VoidCallback onCreateFolder;
  final ValueChanged<ChatFolder> onFolderLongPress;
  final bool reorderEditing;
  final VoidCallback? onExitReorderEditing;
  final ValueChanged<ChatFolder>? onDeleteFolder;
  final void Function(int oldIndex, int newIndex)? onReorderFolders;

  @override
  State<ConversationFolderBar> createState() => _ConversationFolderBarState();
}

class _ConversationFolderBarState extends State<ConversationFolderBar> {
  final _scrollController = ScrollController();
  bool _isDragging = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (widget.reorderEditing) {
      widget.onReorderFolders?.call(oldIndex, newIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.folders.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    final barBackground =
        dark ? colors.surfaceContainerLow : AppTokens.surfaceLight;
    final addForeground =
        dark ? colors.onSurfaceVariant : _FolderBarTokens.addLight;
    final shadowsEnabled =
        !dark && defaultTargetPlatform != TargetPlatform.android;
    final canReorder = widget.reorderEditing && widget.onReorderFolders != null;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 9),
      child: Row(
        children: [
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: barBackground,
                  borderRadius: BorderRadius.circular(AppTokens.rPill),
                  boxShadow: shadowsEnabled
                      ? [
                          BoxShadow(
                            color: _FolderBarTokens.shadow.withValues(
                                alpha: _FolderBarTokens.shadowOpacity),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : const [],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: SizedBox(
                    height: _FolderBarTokens.height,
                    child: ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      primary: false,
                      scrollController: _scrollController,
                      buildDefaultDragHandles: false,
                      padding: EdgeInsets.zero,
                      header: _Segment(
                        label: chinese ? '全部' : 'All',
                        selected: widget.selectedFolderID == null,
                        badge: 0,
                        onTap: () {
                          if (widget.reorderEditing) {
                            widget.onExitReorderEditing?.call();
                          }
                          widget.onSelectAll();
                        },
                      ),
                      itemCount: widget.folders.length,
                      onReorder: _onReorder,
                      onReorderStart: (_) => setState(() => _isDragging = true),
                      onReorderEnd: (_) => setState(() => _isDragging = false),
                      proxyDecorator: (child, index, animation) =>
                          AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) => Material(
                          elevation:
                              3 * Curves.easeOut.transform(animation.value),
                          color: Colors.transparent,
                          shadowColor: _FolderBarTokens.dragShadow,
                          borderRadius: BorderRadius.circular(AppTokens.rPill),
                          child: child,
                        ),
                      ),
                      itemBuilder: (context, index) {
                        final folder = widget.folders[index];
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey<String>(folder.id),
                          index: index,
                          enabled: canReorder,
                          child: _Segment(
                            label: folder.name,
                            selected: widget.selectedFolderID == folder.id,
                            badge: widget.unreadForFolder(folder),
                            notifiable:
                                widget.hasNotifiableUnreadForFolder(folder),
                            onTap: () => widget.onSelectFolder(folder.id),
                            onLongPress: widget.reorderEditing
                                ? null
                                : () => widget.onFolderLongPress(folder),
                            onSecondaryTap: widget.reorderEditing
                                ? null
                                : () => widget.onFolderLongPress(folder),
                            jiggle: widget.reorderEditing && !_isDragging,
                            showClose: widget.reorderEditing &&
                                widget.onDeleteFolder != null,
                            onClose: widget.onDeleteFolder == null
                                ? null
                                : () => widget.onDeleteFolder!(folder),
                            jigglePhaseMs: folder.id.hashCode.abs() % 120,
                            jiggleInvert: folder.id.hashCode.isOdd,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s3),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTokens.rPill),
              onTap: widget.reorderEditing
                  ? widget.onExitReorderEditing
                  : widget.onCreateFolder,
              child: Container(
                width: _FolderBarTokens.height,
                height: _FolderBarTokens.height,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: barBackground,
                  shape: BoxShape.circle,
                  boxShadow: shadowsEnabled
                      ? [
                          BoxShadow(
                            color: _FolderBarTokens.shadow.withValues(
                                alpha: _FolderBarTokens.shadowOpacity),
                            blurRadius: 8,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : const [],
                ),
                child: Icon(
                  widget.reorderEditing
                      ? Icons.check_rounded
                      : Icons.add_rounded,
                  size: _FolderBarTokens.addSize,
                  color: addForeground,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipJiggle extends StatefulWidget {
  const _ChipJiggle(
      {required this.phase, required this.invert, required this.child});
  final Duration phase;
  final bool invert;
  final Widget child;

  @override
  State<_ChipJiggle> createState() => _ChipJiggleState();
}

class _ChipJiggleState extends State<_ChipJiggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: widget.invert ? 1 : 0,
    );
    _delay = Timer(widget.phase, () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.rotate(
          alignment: Alignment.center,
          angle: .045 * (2 * _controller.value - 1),
          child: child,
        ),
        child: widget.child,
      );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
    this.notifiable = true,
    this.onLongPress,
    this.onSecondaryTap,
    this.jiggle = false,
    this.showClose = false,
    this.onClose,
    this.jigglePhaseMs = 0,
    this.jiggleInvert = false,
  });

  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  final bool notifiable;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool jiggle;
  final bool showClose;
  final VoidCallback? onClose;
  final int jigglePhaseMs;
  final bool jiggleInvert;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final badgeText = badge > 99 ? '99+' : '$badge';
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.rPill),
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onSecondaryTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? (dark
                      ? colors.surfaceContainerHighest
                      : _FolderBarTokens.selectedLight)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTokens.rPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: _FolderBarTokens.labelSize,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color:
                          dark ? colors.onSurface : AppTokens.textPrimaryLight,
                      height: _FolderBarTokens.labelHeight,
                    )),
                if (showClose) ...[
                  const SizedBox(width: 2),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    child: Icon(Icons.close_rounded,
                        size: _FolderBarTokens.closeSize,
                        color: dark
                            ? colors.onSurfaceVariant
                            : _FolderBarTokens.addLight),
                  ),
                ] else if (badge > 0) ...[
                  const SizedBox(width: AppTokens.s2),
                  Container(
                    constraints: const BoxConstraints(
                        minWidth: _FolderBarTokens.badgeSize,
                        minHeight: _FolderBarTokens.badgeSize),
                    height: _FolderBarTokens.badgeSize,
                    padding: EdgeInsets.symmetric(
                        horizontal: badgeText.length > 1 ? 4 : 0),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: notifiable
                          ? _FolderBarTokens.unread
                          : dark
                              ? colors.secondaryContainer
                              : _FolderBarTokens.quietBadgeLight,
                      borderRadius: BorderRadius.circular(AppTokens.rPill),
                    ),
                    child: Text(badgeText,
                        style: TextStyle(
                          fontSize: _FolderBarTokens.badgeFontSize,
                          fontWeight: FontWeight.w600,
                          color: !notifiable && dark
                              ? colors.onSecondaryContainer
                              : AppTokens.onAccent,
                          height: 1,
                        )),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (jiggle && !MediaQuery.disableAnimationsOf(context)) {
      content = _ChipJiggle(
        phase: Duration(milliseconds: jigglePhaseMs),
        invert: jiggleInvert,
        child: content,
      );
    }
    return content;
  }
}
