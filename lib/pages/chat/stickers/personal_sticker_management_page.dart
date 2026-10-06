import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart'
    show AppSystemBars, GlassAppBar, Styles;

import 'personal_sticker_store.dart';

class PersonalStickerManagementPage extends StatefulWidget {
  const PersonalStickerManagementPage({
    super.key,
    required this.store,
    required this.onAdd,
  });

  final PersonalStickerStore store;
  final Future<void> Function() onAdd;

  @override
  State<PersonalStickerManagementPage> createState() =>
      _PersonalStickerManagementPageState();
}

class _PersonalStickerManagementPageState
    extends State<PersonalStickerManagementPage> {
  bool _loadingAll = false;
  bool _organizing = false;
  bool _busy = false;
  final Set<String> _selected = {};
  List<String>? _localOrder;
  List<String>? _dragStartOrder;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (_loadingAll || widget.store.isDisposed) return;
    setState(() => _loadingAll = true);
    try {
      while (widget.store.loading) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted || widget.store.isDisposed) return;
      }
      if (!mounted || widget.store.isDisposed) return;
      if (widget.store.items.isEmpty || widget.store.error != null) {
        await widget.store.refresh();
      }
      while (mounted &&
          !widget.store.isDisposed &&
          widget.store.nextCursor != null &&
          widget.store.error == null) {
        final cursor = widget.store.nextCursor;
        await widget.store.loadMore();
        // A cancelled session or a concurrent loader can return without a page.
        // Never spin on the same cursor, even when no error was published.
        if (widget.store.nextCursor == cursor) break;
      }
    } finally {
      if (mounted) setState(() => _loadingAll = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('操作失败：$error')));
  }

  Future<void> _add() async {
    try {
      await widget.onAdd();
    } catch (error) {
      _showError(error);
    }
  }

  void _preview(PersonalSticker item) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .65,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                item.previewURL,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 200,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            IconButton.filledTonal(
              tooltip: '关闭预览',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除选中的 ${_selected.length} 个表情？'),
        content: const Text('已发送的消息不会受到影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      for (final item in widget.store.items.toList()) {
        if (!_selected.contains(item.id)) continue;
        await widget.store.remove(item);
        _selected.remove(item.id);
      }
      if (mounted) setState(() => _organizing = false);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _previewMove(String sourceID, int targetIndex) {
    final original = _dragStartOrder;
    if (original == null || _busy) return;
    final ids = List<String>.of(original);
    if (!ids.remove(sourceID)) return;
    ids.insert(targetIndex.clamp(0, ids.length), sourceID);
    if (listEquals(_localOrder, ids)) return;
    setState(() => _localOrder = ids);
  }

  Future<void> _commitMove() async {
    final ids = _localOrder;
    final original = _dragStartOrder;
    if (ids == null || original == null || _busy) return;
    _dragStartOrder = null;
    if (listEquals(ids, original)) {
      setState(() => _localOrder = null);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.store.reorder(ids);
    } on StickerApiException catch (error) {
      _showError(error.code == 20025 ? '收藏已在其他设备改变，请重试' : error);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _localOrder = null;
          _dragStartOrder = null;
          _busy = false;
        });
      }
    }
  }

  void _cancelDrag() {
    if (!_busy && _dragStartOrder != null) {
      setState(() {
        _dragStartOrder = null;
        _localOrder = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final storedItems = widget.store.items;
        final byID = {for (final item in storedItems) item.id: item};
        final items = _localOrder == null
            ? storedItems
            : [
                for (final id in _localOrder!)
                  if (byID[id] != null) byID[id]!,
              ];
        return Scaffold(
          backgroundColor: Styles.c_F4F5F7,
          appBar: GlassAppBar(
            toolbarHeight: kToolbarHeight,
            backgroundColor: Styles.c_F4F5F7,
            systemOverlayStyle: AppSystemBars.styleFor(Styles.c_F4F5F7),
            elevation: 0,
            centerTitle: true,
            leadingWidth: 72,
            leading: TextButton(
              onPressed: () {
                if (_organizing) {
                  setState(() {
                    _organizing = false;
                    _selected.clear();
                  });
                } else {
                  Navigator.pop(context);
                }
              },
              child: Text(_organizing ? '取消' : '关闭'),
            ),
            title: Text('添加的单个表情 (${items.length})',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            actions: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _organizing = !_organizing;
                          _selected.clear();
                        }),
                child: Text(_organizing ? '完成' : '整理'),
              ),
            ],
          ),
          body: Column(children: [
            if (_loadingAll || _busy || widget.store.saving)
              const LinearProgressIndicator(minHeight: 2),
            if (widget.store.error != null)
              ListTile(
                title: const Text('加载失败，点击重试'),
                subtitle: Text(widget.store.error!),
                onTap: _loadAll,
              ),
            Expanded(
              child: DragTarget<String>(
                onWillAcceptWithDetails: (_) =>
                    !_busy && !_loadingAll && widget.store.nextCursor == null,
                onAcceptWithDetails: (_) => _commitMove(),
                builder: (context, _, __) => GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                      8,
                      8,
                      8,
                      16 +
                          (_organizing
                              ? 0
                              : MediaQuery.paddingOf(context).bottom)),
                  itemCount: items.length + 1,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 2,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _tile(
                        child: InkWell(
                          key: const ValueKey('management-add-tile'),
                          onTap:
                              _organizing || widget.store.saving ? null : _add,
                          child: Icon(Icons.add,
                              size: 46,
                              color: colors.onSurfaceVariant
                                  .withValues(alpha: .5)),
                        ),
                      );
                    }
                    final item = items[index - 1];
                    final selected = _selected.contains(item.id);
                    final tile = _tile(
                      child: InkWell(
                        key: ValueKey('management-sticker-${item.id}'),
                        onTap: _organizing
                            ? () => setState(() {
                                  if (!selected) {
                                    _selected.add(item.id);
                                  } else {
                                    _selected.remove(item.id);
                                  }
                                })
                            : () => _preview(item),
                        child: Stack(fit: StackFit.expand, children: [
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: Image.network(item.previewURL,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.broken_image_outlined)),
                            ),
                          ),
                          if (selected)
                            Container(
                                color: colors.primary.withValues(alpha: .14)),
                          if (item.isVideo)
                            const Center(
                                child: Icon(Icons.play_circle_fill,
                                    color: Colors.white, size: 30)),
                          if (_organizing)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: selected ? colors.primary : Colors.grey,
                                size: 24,
                              ),
                            ),
                        ]),
                      ),
                    );
                    return DragTarget<String>(
                      key: ValueKey('sticker-target-$index'),
                      onWillAcceptWithDetails: (details) =>
                          !_busy &&
                          !_loadingAll &&
                          widget.store.nextCursor == null,
                      onMove: (details) =>
                          _previewMove(details.data, index - 1),
                      onAcceptWithDetails: (_) => _commitMove(),
                      builder: (context, candidates, _) => DecoratedBox(
                        decoration: BoxDecoration(
                          border: candidates.isEmpty
                              ? null
                              : Border.all(color: colors.primary, width: 2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: LongPressDraggable<String>(
                          key: ValueKey('sticker-drag-${item.id}'),
                          data: item.id,
                          onDragStarted: () {
                            _dragStartOrder = widget.store.items
                                .map((item) => item.id)
                                .toList();
                          },
                          onDragEnd: (details) {
                            if (!details.wasAccepted) _cancelDrag();
                          },
                          maxSimultaneousDrags: _busy ||
                                  _loadingAll ||
                                  widget.store.nextCursor != null
                              ? 0
                              : 1,
                          feedback: Material(
                            color: Colors.transparent,
                            elevation: 8,
                            borderRadius: BorderRadius.circular(8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(item.previewURL,
                                  width: 76,
                                  height: 76,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox(width: 76, height: 76)),
                            ),
                          ),
                          childWhenDragging: Opacity(opacity: .3, child: tile),
                          child: tile,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_organizing)
              ColoredBox(
                color: colors.surface,
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    height: 58,
                    child: Row(children: [
                      const Spacer(),
                      TextButton(
                        onPressed: _selected.isEmpty ? null : _deleteSelected,
                        child: Text('删除',
                            style: TextStyle(
                                color: _selected.isEmpty
                                    ? colors.onSurfaceVariant
                                    : colors.error)),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }

  Widget _tile({required Widget child}) => Center(
        child: FractionallySizedBox(
          widthFactor: .84,
          heightFactor: .84,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      );
}
