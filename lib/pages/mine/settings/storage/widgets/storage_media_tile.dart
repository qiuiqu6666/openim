import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../pages/storage_media_repository.dart';
import '../../pages/storage_widgets.dart';
import '../../widgets/settings_widgets.dart';
import 'storage_media_thumbnail.dart';

/// Owns its mounted render key; scrolling off screen unregisters hit testing.
class StorageMediaTile extends StatefulWidget {
  const StorageMediaTile({
    super.key,
    required this.item,
    required this.selection,
    required this.isSelecting,
    required this.isSelected,
    required this.onMount,
    required this.onUnmount,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final StorageMediaItem item;
  final ValueListenable<int> selection;
  final bool Function() isSelecting;
  final bool Function() isSelected;
  final void Function(String, GlobalKey) onMount;
  final void Function(String, GlobalKey) onUnmount;
  final VoidCallback onTap;
  final void Function(Offset) onDragStart;
  final void Function(Offset) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  State<StorageMediaTile> createState() => _StorageMediaTileState();
}

class _StorageMediaTileState extends State<StorageMediaTile> {
  final _renderKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.onMount(widget.item.id, _renderKey);
  }

  @override
  void dispose() {
    widget.onUnmount(widget.item.id, _renderKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        key: _renderKey,
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (details) =>
            widget.onDragStart(details.globalPosition),
        onLongPressMoveUpdate: (details) =>
            widget.onDragUpdate(details.globalPosition),
        onLongPressEnd: (_) => widget.onDragEnd(),
        onLongPressCancel: widget.onDragEnd,
        onTap: widget.onTap,
        child: ValueListenableBuilder<int>(
          valueListenable: widget.selection,
          child: StorageMediaThumbnail(item: widget.item),
          builder: (context, _, thumbnail) {
            final selected = widget.isSelected();
            final dark = settingsIsDark(context);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(children: [
                    Positioned.fill(child: thumbnail!),
                    if (widget.isSelecting())
                      Positioned(
                        top: AppTokens.s2,
                        right: AppTokens.s2,
                        child: Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color:
                              selected ? AppTokens.accent : AppTokens.onAccent,
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: AppTokens.s2),
                Center(
                  child: Text(storageFormatBytes(widget.item.bytes),
                      maxLines: 1,
                      style: TextStyle(
                        color: AppTokens.textSecondary(dark: dark),
                        fontSize: AppTokens.captionFontSize,
                      )),
                ),
              ],
            );
          },
        ),
      );
}
