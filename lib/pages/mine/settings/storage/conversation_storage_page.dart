import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../widgets/settings_widgets.dart';
import '../pages/storage_media_repository.dart';
import '../pages/storage_widgets.dart';
import 'storage_media_catalog.dart';
import 'widgets/storage_media_tile.dart';

class ConversationStoragePage extends StatefulWidget {
  const ConversationStoragePage({
    super.key,
    required this.name,
    required this.conversationID,
    required this.source,
    required this.revision,
    required this.repository,
    required this.onRemoved,
    this.initialType,
  });

  final String name;
  final String conversationID;
  final List<StorageMediaItem> source;
  final ValueListenable<int> revision;
  final StorageMediaRepository repository;
  final ValueChanged<Set<String>> onRemoved;
  final StorageMediaType? initialType;

  @override
  State<ConversationStoragePage> createState() =>
      _ConversationStoragePageState();
}

class _ConversationStoragePageState extends State<ConversationStoragePage> {
  final _selected = <String>{};
  bool _selecting = false;
  bool _deleting = false;
  bool _oldestFirst = false;

  final _scrollController = ScrollController();
  final _viewportKey = GlobalKey();
  final _tileKeys = <String, GlobalKey>{};
  final _selectionRevision = ValueNotifier<int>(0);
  StorageMediaCatalog? _catalog;
  Widget? _mediaView;
  int _selectedBytes = 0;
  int _catalogGeneration = 0;
  bool _opening = false;
  Timer? _dragTimer;
  Offset? _dragPosition;
  int? _dragAnchor;
  List<StorageMediaItem> _dragItems = [];
  Map<String, int> _dragIndices = {};
  Set<String> _dragBaseline = {};
  bool _dragAdding = true;

  void _endDrag() {
    _dragTimer?.cancel();
    _dragTimer = null;
    _dragPosition = null;
    _dragAnchor = null;
    _dragItems = [];
    _dragIndices = {};
  }

  void _startDrag(StorageMediaItem item, Offset position) {
    if (_deleting) return;
    _endDrag();
    _dragItems = _items;
    _dragIndices = {
      for (var i = 0; i < _dragItems.length; i++) _dragItems[i].id: i,
    };
    _dragAnchor = _dragItems.indexWhere((entry) => entry.id == item.id);
    _dragBaseline = Set.of(_selected);
    _dragAdding = !_selected.contains(item.id);
    _dragPosition = position;
    _changeSelection(() {
      _selecting = true;
      _dragAdding ? _selected.add(item.id) : _selected.remove(item.id);
    });
    _dragTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || _dragPosition == null || !_scrollController.hasClients) {
        return;
      }
      final box = _viewportKey.currentContext?.findRenderObject();
      if (box is! RenderBox) return;
      final local = box.globalToLocal(_dragPosition!);
      const edge = AppTokens.listItemHeight;
      final speed = local.dy < edge
          ? -(edge - local.dy) / edge
          : local.dy > box.size.height - edge
              ? (local.dy - box.size.height + edge) / edge
              : 0.0;
      if (speed != 0) {
        final scroll = _scrollController.position;
        _scrollController.jumpTo(
            (scroll.pixels + speed.clamp(-1.0, 1.0) * AppTokens.s4)
                .clamp(scroll.minScrollExtent, scroll.maxScrollExtent));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _dragPosition != null) _updateDrag(_dragPosition!);
        });
      }
    });
  }

  void _updateDrag(Offset position) {
    if (_dragAnchor == null || _dragAnchor! < 0) return;
    _dragPosition = position;
    for (final entry in _tileKeys.entries) {
      final i = _dragIndices[entry.key];
      if (i == null) continue;
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (!rect.inflate(AppTokens.s3).contains(position)) continue;
      final start = i < _dragAnchor! ? i : _dragAnchor!;
      final end = i > _dragAnchor! ? i : _dragAnchor!;
      final next = Set<String>.of(_dragBaseline);
      for (var j = start; j <= end; j++) {
        _dragAdding
            ? next.add(_dragItems[j].id)
            : next.remove(_dragItems[j].id);
      }
      if (!setEquals(next, _selected)) {
        _changeSelection(() {
          _selected
            ..clear()
            ..addAll(next);
        });
      }
      break;
    }
  }

  @override
  void initState() {
    super.initState();
    _rebuildCatalog();
    widget.revision.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mediaView = null;
  }

  @override
  void didUpdateWidget(covariant ConversationStoragePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      oldWidget.revision.removeListener(_refresh);
      widget.revision.addListener(_refresh);
    }
    if (oldWidget.source != widget.source ||
        oldWidget.conversationID != widget.conversationID ||
        oldWidget.initialType != widget.initialType ||
        oldWidget.revision != widget.revision) {
      _endDrag();
      _rebuildCatalog();
    }
  }

  void _refresh() {
    if (!mounted) return;
    _endDrag();
    setState(_rebuildCatalog);
    _selectionRevision.value++;
  }

  @override
  void dispose() {
    _endDrag();
    _scrollController.dispose();
    _selectionRevision.dispose();
    widget.revision.removeListener(_refresh);
    super.dispose();
  }

  List<StorageMediaItem> get _items => _catalog!.items;

  void _rebuildCatalog() {
    _catalog = StorageMediaCatalog(
      source: widget.source,
      conversationID: widget.conversationID,
      type: widget.initialType,
      oldestFirst: _oldestFirst,
      now: DateTime.now(),
    );
    _catalogGeneration++;
    _selected.removeWhere((id) => !_catalog!.byID.containsKey(id));
    _selectedBytes = _selectionBytes();
    _mediaView = null;
  }

  int _selectionBytes() => _selected.fold<int>(
      0, (sum, id) => sum + (_catalog!.byID[id]?.bytes ?? 0));

  void _changeSelection(VoidCallback change) {
    setState(() {
      change();
      _selectedBytes = _selectionBytes();
    });
    _selectionRevision.value++;
  }

  Future<void> _removeSelected(List<StorageMediaItem> items) async {
    if (_selected.isEmpty || _deleting) return;
    final selected =
        items.where((item) => _selected.contains(item.id)).toList();
    final bytes = selected.fold<int>(0, (sum, item) => sum + item.bytes);
    final confirmed = await showStorageConfirm(
      context,
      title: settingsText(context, zh: '删除所选文件？', en: 'Delete selected files?'),
      description: settingsText(context,
          zh: '将释放约 ${storageFormatBytes(bytes)} 本机空间。聊天消息不会删除，需要查看时可重新下载。',
          en: 'This frees about ${storageFormatBytes(bytes)} locally. Chat messages stay and files can be downloaded again.'),
      action: settingsText(context, zh: '删除', en: 'Delete'),
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.repository.removeLocalFiles(selected);
      widget.onRemoved(selected.map((item) => item.id).toSet());
      if (!mounted) return;
      _changeSelection(() {
        _selected.clear();
        _selecting = false;
      });
      await showStorageComplete(context, bytes);
    } catch (_) {
      if (mounted) {
        showSettingsMessage(
            context,
            settingsText(context,
                zh: '部分文件未能删除，请重试',
                en: 'Some files could not be deleted. Retry.'));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _buildMediaView(BuildContext context) {
    final dark = settingsIsDark(context);
    return CustomScrollView(
      key: _viewportKey,
      controller: _scrollController,
      slivers: [
        for (final section in _catalog!.sections.entries) ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
                child: Row(children: [
                  Text(
                    section.key == 'today'
                        ? settingsText(context, zh: '今天', en: 'Today')
                        : section.key == 'week'
                            ? settingsText(context, zh: '本周', en: 'This week')
                            : section.key,
                    style: TextStyle(
                      color: AppTokens.textPrimary(dark: dark),
                      fontWeight: FontWeight.w600,
                      fontSize: AppTokens.secondaryFontSize,
                    ),
                  ),
                  const SizedBox(width: AppTokens.s3),
                  Text('${section.value.length}',
                      style: TextStyle(
                        color: AppTokens.textSecondary(dark: dark),
                        fontSize: AppTokens.captionFontSize,
                      )),
                ]),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: AppTokens.s3,
                mainAxisSpacing: AppTokens.s4,
                childAspectRatio: .84,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = section.value[index];
                  return StorageMediaTile(
                    key: ValueKey(item.id),
                    item: item,
                    selection: _selectionRevision,
                    isSelecting: () => _selecting,
                    isSelected: () => _selected.contains(item.id),
                    onMount: (id, key) => _tileKeys[id] = key,
                    onUnmount: (id, key) {
                      if (identical(_tileKeys[id], key)) _tileKeys.remove(id);
                    },
                    onTap: () => _openItem(item),
                    onDragStart: (position) => _startDrag(item, position),
                    onDragUpdate: _updateDrag,
                    onDragEnd: _endDrag,
                  );
                },
                childCount: section.value.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s6)),
      ],
    );
  }

  Future<void> _openItem(StorageMediaItem item) async {
    if (_selecting) {
      _changeSelection(() {
        _selected.contains(item.id)
            ? _selected.remove(item.id)
            : _selected.add(item.id);
      });
      return;
    }
    if (item.type == StorageMediaType.file) {
      IMUtils.previewFile(item.message);
      return;
    }
    if (_opening) return;
    _opening = true;
    final generation = _catalogGeneration;
    try {
      final gallery = _items.where((media) => media.type == item.type).toList();
      final sources = <MediaSource>[];
      // Bound asynchronous filesystem work when a conversation has many media.
      for (var offset = 0; offset < gallery.length; offset += 12) {
        sources.addAll(
            await Future.wait(gallery.skip(offset).take(12).map(_mediaSource)));
        if (!mounted || generation != _catalogGeneration) return;
      }
      if (!mounted || generation != _catalogGeneration) return;
      IMUtils.previewMediaFile(
        context: context,
        message: item.message,
        sources: sources,
        initialIndex: gallery.indexWhere((media) => media.id == item.id),
        showCounter: true,
      );
    } finally {
      _opening = false;
    }
  }

  Future<MediaSource> _mediaSource(StorageMediaItem media) async {
    final message = media.message;
    final video = media.type == StorageMediaType.video;
    final localPath =
        video ? message.videoElem?.videoPath : message.pictureElem?.sourcePath;
    bool exists = false;
    if (localPath != null && localPath.isNotEmpty) {
      try {
        exists = await File(localPath).exists();
      } catch (_) {/* Fall back to the recoverable remote copy. */}
    }
    final availablePath = exists
        ? localPath
        : video
            ? null
            : media.previewPath ??
                (media.localPaths.isNotEmpty ? media.localPaths.first : null);
    return MediaSource(
      url: video
          ? message.videoElem?.videoUrl
          : message.pictureElem?.sourcePicture?.url,
      thumbnail: media.previewPath ??
          (video
              ? message.videoElem?.snapshotUrl
              : message.pictureElem?.snapshotPicture?.url) ??
          '',
      file: availablePath == null ? null : File(availablePath),
      isVideo: video,
      tag: message.clientMsgID,
      senderName: message.senderNickname?.isNotEmpty == true
          ? message.senderNickname
          : message.sendID,
      sentAt: media.time,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final items = _items;
    final now = DateTime.now();
    if (_catalog!.day != DateTime(now.year, now.month, now.day)) {
      _rebuildCatalog();
    }
    final selectedBytes = _selectedBytes;

    return SettingsScaffold(
      title: _selecting
          ? settingsText(context,
              zh: '已选择 ${_selected.length} 项',
              en: '${_selected.length} selected')
          : settingsText(context, zh: '聊天文件', en: 'Chat Files'),
      leading: _selecting
          ? TextButton(
              onPressed: () => _changeSelection(() {
                _selecting = false;
                _selected.clear();
              }),
              child: Text(settingsText(context, zh: '取消', en: 'Cancel')),
            )
          : null,
      actions: [
        TextButton(
          onPressed: () => _changeSelection(() {
            if (_selecting) {
              if (_selected.length == items.length) {
                _selected.clear();
              } else {
                _selected.addAll(items.map((item) => item.id));
              }
            } else {
              _selecting = true;
            }
          }),
          child: Text(_selecting
              ? settingsText(context, zh: '全选', en: 'Select all')
              : settingsText(context, zh: '选择', en: 'Select')),
        ),
      ],
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(
              AppTokens.s4, AppTokens.s3, AppTokens.s4, AppTokens.s3),
          padding: const EdgeInsets.fromLTRB(
              AppTokens.s4, AppTokens.s4, AppTokens.s4, AppTokens.s2),
          decoration: BoxDecoration(
              color: AppTokens.surface(dark: dark),
              borderRadius: BorderRadius.circular(AppTokens.rMd)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppTokens.textPrimary(dark: dark),
                    fontSize: AppTokens.listTitleFontSize,
                    fontWeight: FontWeight.w600)),
            Row(children: [
              Expanded(
                  child: Text(
                      settingsText(context,
                          zh:
                              '${items.length} 个项目 · ${storageFormatBytes(_catalog!.totalBytes)}',
                          en:
                              '${items.length} items · ${storageFormatBytes(_catalog!.totalBytes)}'),
                      style: TextStyle(
                          color: AppTokens.textSecondary(dark: dark),
                          fontSize: AppTokens.captionFontSize),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              if (!_selecting)
                TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: AppTokens.textSecondary(dark: dark)),
                    onPressed: () => setState(() {
                          _endDrag();
                          _oldestFirst = !_oldestFirst;
                          _rebuildCatalog();
                        }),
                    icon:
                        const Icon(Icons.swap_vert_rounded, size: AppTokens.s6),
                    label: Text(_oldestFirst
                        ? settingsText(context, zh: '时间升序', en: 'Oldest first')
                        : settingsText(context,
                            zh: '时间倒序', en: 'Newest first'))),
            ]),
          ]),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    settingsText(context, zh: '暂无本机文件', en: 'No local files'),
                    style:
                        TextStyle(color: AppTokens.textSecondary(dark: dark)),
                  ),
                )
              : (_mediaView ??= _buildMediaView(context)),
        ),
      ]),
      bottom: _selecting
          ? Container(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.s5, AppTokens.s3, AppTokens.s5, AppTokens.s5),
              color: AppTokens.background(dark: dark),
              child: SizedBox(
                width: double.infinity,
                child: SettingsDestructiveButton(
                  soft: true,
                  text: settingsText(context,
                      zh: '删除（${storageFormatBytes(selectedBytes)}）',
                      en: 'Delete (${storageFormatBytes(selectedBytes)})'),
                  loadingText:
                      settingsText(context, zh: '正在删除…', en: 'Deleting…'),
                  loading: _deleting,
                  onPressed: _selected.isEmpty || _deleting
                      ? null
                      : () => _removeSelected(items),
                ),
              ),
            )
          : null,
      children: const [],
    );
  }
}
