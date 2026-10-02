import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_navigation.dart';
import '../widgets/settings_widgets.dart';
import 'storage_media_repository.dart';
import 'storage_widgets.dart';

class ChatStoragePage extends StatefulWidget {
  const ChatStoragePage({
    super.key,
    this.initialType,
    this.initialMinBytes = 0,
    this.initialOlderDays = 0,
  });

  final StorageMediaType? initialType;
  final int initialMinBytes;
  final int initialOlderDays;

  @override
  State<ChatStoragePage> createState() => _ChatStoragePageState();
}

class _ChatStoragePageState extends State<ChatStoragePage> {
  final _repository = StorageMediaRepository();
  final _searchController = TextEditingController();
  final _items = <StorageMediaItem>[];
  final _seen = <String>{};
  final _revision = ValueNotifier<int>(0);
  Timer? _searchDebounce;
  int _generation = 0;
  int _tab = 0;
  int _minBytes = 0;
  int _olderDays = 0;
  bool _loading = true;
  bool _failed = false;
  bool _partial = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = widget.initialType == null ? 0 : widget.initialType!.index + 1;
    _minBytes = widget.initialMinBytes;
    _olderDays = widget.initialOlderDays;
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 180), () {
        if (mounted) setState(() => _query = _searchController.text.trim());
      });
    });
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _partial = false;
      _items.clear();
      _seen.clear();
    });
    _revision.value++;
    try {
      const pageSize = 100;
      for (var page = 1; page <= 50; page++) {
        if (!mounted || generation != _generation) return;
        final result =
            await OpenIM.iMManager.messageManager.searchLocalMessages(
          messageTypeList: const [
            MessageType.picture,
            MessageType.video,
            MessageType.file,
          ],
          pageIndex: page,
          count: pageSize,
        );
        if (!mounted || generation != _generation) return;
        final conversations = result.searchResultItems ?? [];
        final entries = <(Message, SearchResultItems)>[];
        for (final conversation in conversations) {
          for (final message in conversation.messageList ?? <Message>[]) {
            if (message.clientMsgID != null &&
                _seen.add(message.clientMsgID!)) {
              entries.add((message, conversation));
            }
          }
        }
        if (entries.isEmpty) break;
        final resolved = <StorageMediaItem>[];
        // Limit simultaneous cache database reads on large chat histories.
        for (var offset = 0; offset < entries.length; offset += 12) {
          final batch = entries.skip(offset).take(12);
          final found = await Future.wait(batch.map(
            (entry) => _repository.resolve(entry.$1, entry.$2),
          ));
          resolved.addAll(found.whereType<StorageMediaItem>());
        }
        if (!mounted || generation != _generation) return;
        setState(() => _items.addAll(resolved));
        _revision.value++;
        final reportedTotal = result.totalCount ?? 0;
        if (reportedTotal > 0
            ? _seen.length >= reportedTotal
            : entries.length < pageSize) {
          break;
        }
        if (page == 50) setState(() => _partial = true);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  List<StorageMediaItem> get _visibleItems {
    final threshold = _olderDays == 0
        ? null
        : DateTime.now().subtract(Duration(days: _olderDays));
    return _items.where((item) {
      if (_tab > 0 && item.type.index != _tab - 1) return false;
      if (item.bytes < _minBytes) return false;
      if (threshold != null && !item.time.isBefore(threshold)) return false;
      return true;
    }).toList();
  }

  Future<void> _showFilter() async {
    var tab = _tab;
    var minBytes = _minBytes;
    var olderDays = _olderDays;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) {
          final dark = settingsIsDark(sheetContext);
          Widget group(String title, List<(String, int)> options, int selected,
              ValueChanged<int> onSelected) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        color: AppTokens.textPrimary(dark: dark),
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: AppTokens.s4),
                  Wrap(
                    spacing: AppTokens.s3,
                    runSpacing: AppTokens.s3,
                    children: options.map((option) {
                      final active = option.$2 == selected;
                      return ChoiceChip(
                        label: Text(option.$1),
                        selected: active,
                        onSelected: (_) => update(() => onSelected(option.$2)),
                        selectedColor: AppTokens.accent.withValues(alpha: .12),
                        backgroundColor: AppTokens.surfaceAlt(dark: dark),
                        side: BorderSide(
                          color: active ? AppTokens.accent : Colors.transparent,
                        ),
                        labelStyle: TextStyle(
                          color: active
                              ? AppTokens.accent
                              : AppTokens.textPrimary(dark: dark),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppTokens.s6),
                ]);
          }

          return SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(AppTokens.s6),
              decoration: BoxDecoration(
                color: AppTokens.surface(dark: dark),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTokens.rLg),
                ),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      settingsText(context, zh: '筛选', en: 'Filter'),
                      style: TextStyle(
                        color: AppTokens.textPrimary(dark: dark),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                const SizedBox(height: AppTokens.s4),
                group(
                    settingsText(context, zh: '文件类型', en: 'File type'),
                    [
                      (settingsText(context, zh: '全部', en: 'All'), 0),
                      (settingsText(context, zh: '图片', en: 'Photos'), 1),
                      (settingsText(context, zh: '视频', en: 'Videos'), 2),
                      (settingsText(context, zh: '文件', en: 'Files'), 3),
                    ],
                    tab,
                    (value) => tab = value),
                group(
                    settingsText(context, zh: '文件大小', en: 'File size'),
                    [
                      (settingsText(context, zh: '全部', en: 'All'), 0),
                      (
                        settingsText(context, zh: '大于 10 MB', en: 'Over 10 MB'),
                        10 << 20
                      ),
                      (
                        settingsText(context, zh: '大于 50 MB', en: 'Over 50 MB'),
                        50 << 20
                      ),
                      (
                        settingsText(context,
                            zh: '大于 100 MB', en: 'Over 100 MB'),
                        100 << 20
                      ),
                    ],
                    minBytes,
                    (value) => minBytes = value),
                group(
                    settingsText(context, zh: '时间', en: 'Time'),
                    [
                      (settingsText(context, zh: '全部', en: 'All'), 0),
                      (
                        settingsText(context,
                            zh: '1 个月前', en: 'Older than 1 month'),
                        30
                      ),
                      (
                        settingsText(context,
                            zh: '3 个月前', en: 'Older than 3 months'),
                        90
                      ),
                      (
                        settingsText(context,
                            zh: '1 年前', en: 'Older than 1 year'),
                        365
                      ),
                    ],
                    olderDays,
                    (value) => olderDays = value),
                Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => update(() {
                        tab = 0;
                        minBytes = 0;
                        olderDays = 0;
                      }),
                      child: Text(settingsText(context, zh: '重置', en: 'Reset')),
                    ),
                  ),
                  const SizedBox(width: AppTokens.s4),
                  Expanded(
                    child: storagePrimaryButton(
                      sheetContext,
                      label: settingsText(context, zh: '确定', en: 'Apply'),
                      onPressed: () => Navigator.pop(sheetContext, true),
                    ),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        _tab = tab;
        _minBytes = minBytes;
        _olderDays = olderDays;
      });
    }
  }

  @override
  void dispose() {
    ++_generation;
    _searchDebounce?.cancel();
    _searchController.dispose();
    _revision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final color = AppTokens.textPrimary(dark: dark);
    final secondary = AppTokens.textSecondary(dark: dark);
    final visible = _visibleItems;
    final groups = <String, List<StorageMediaItem>>{};
    for (final item in visible) {
      if (_query.isNotEmpty &&
          !item.conversationName.toLowerCase().contains(_query.toLowerCase())) {
        continue;
      }
      groups.putIfAbsent(item.conversationID, () => []).add(item);
    }
    final rows = groups.entries.toList()
      ..sort((a, b) => b.value
          .fold<int>(0, (sum, e) => sum + e.bytes)
          .compareTo(a.value.fold<int>(0, (sum, e) => sum + e.bytes)));

    return SettingsScaffold(
      title: settingsText(context, zh: '聊天存储空间', en: 'Chat Storage'),
      actions: [
        TextButton(
          onPressed: _showFilter,
          child: Text(settingsText(context, zh: '筛选', en: 'Filter')),
        ),
      ],
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(
              AppTokens.s4, AppTokens.s4, AppTokens.s4, AppTokens.s3),
          padding: const EdgeInsets.all(AppTokens.s2),
          decoration: BoxDecoration(
            color: AppTokens.surfaceAlt(dark: dark),
            borderRadius: BorderRadius.circular(AppTokens.rMd),
          ),
          child: Row(children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: AppTokens.s3),
                    decoration: BoxDecoration(
                      color: _tab == i
                          ? AppTokens.surface(dark: dark)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppTokens.rSm),
                    ),
                    child: Text(
                      [
                        settingsText(context, zh: '全部', en: 'All'),
                        settingsText(context, zh: '图片', en: 'Photos'),
                        settingsText(context, zh: '视频', en: 'Videos'),
                        settingsText(context, zh: '文件', en: 'Files'),
                      ][i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _tab == i ? AppTokens.accent : secondary,
                        fontWeight:
                            _tab == i ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTokens.s4, 0, AppTokens.s4, AppTokens.s3),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: settingsText(context,
                  zh: '搜索会话名称', en: 'Search conversations'),
              prefixIcon: Icon(Icons.search_rounded, color: secondary),
              filled: true,
              fillColor: AppTokens.surface(dark: dark),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.rMd),
                borderSide: BorderSide.none,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  vertical: AppTokens.s4, horizontal: AppTokens.s5),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_partial)
          Padding(
            padding: const EdgeInsets.all(AppTokens.s3),
            child: Text(
                settingsText(context,
                    zh: '记录较多，仅显示前 5000 条',
                    en: 'Showing the first 5,000 records'),
                style: TextStyle(color: secondary)),
          ),
        Expanded(
          child: _failed && rows.isEmpty
              ? Center(
                  child: TextButton(
                    onPressed: _load,
                    child: Text(settingsText(context,
                        zh: '读取失败，点击重试', en: 'Could not load. Retry')),
                  ),
                )
              : rows.isEmpty
                  ? Center(
                      child: Text(
                        _loading
                            ? settingsText(context,
                                zh: '正在查找本机聊天文件…',
                                en: 'Finding local chat files…')
                            : settingsText(context,
                                zh: '暂无本机聊天文件', en: 'No local chat files'),
                        style: TextStyle(color: secondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                          AppTokens.s4, 0, AppTokens.s4, AppTokens.s6),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppTokens.s3),
                      itemBuilder: (context, index) {
                        final entry = rows[index];
                        final items = entry.value;
                        final total =
                            items.fold<int>(0, (sum, item) => sum + item.bytes);
                        return Material(
                          color: AppTokens.surface(dark: dark),
                          borderRadius: BorderRadius.circular(AppTokens.rLg),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppTokens.rLg),
                            onTap: () async {
                              await openSettingsPage<void>(
                                context,
                                ConversationStoragePage(
                                  name: items.first.conversationName,
                                  conversationID: entry.key,
                                  source: _items,
                                  revision: _revision,
                                  repository: _repository,
                                  initialType: _tab > 0
                                      ? StorageMediaType.values[_tab - 1]
                                      : null,
                                  onRemoved: (removed) => setState(() {
                                    _items.removeWhere(
                                      (item) => removed.contains(item.id),
                                    );
                                    _revision.value++;
                                  }),
                                ),
                              );
                              if (mounted) await _load();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(AppTokens.s4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppTokens.accent,
                                    backgroundImage: items
                                                .first
                                                .conversationFaceURL
                                                ?.isNotEmpty ==
                                            true
                                        ? NetworkImage(
                                            items.first.conversationFaceURL!)
                                        : null,
                                    child: items.first.conversationFaceURL
                                                ?.isNotEmpty ==
                                            true
                                        ? null
                                        : const Icon(Icons.people_outline,
                                            color: AppTokens.onAccent),
                                  ),
                                  const SizedBox(width: AppTokens.s4),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Expanded(
                                            child: Text(
                                              items.first.conversationName
                                                      .isEmpty
                                                  ? entry.key
                                                  : items
                                                      .first.conversationName,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: color,
                                                fontSize:
                                                    AppTokens.listTitleFontSize,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Icon(Icons.chevron_right_rounded,
                                              color: secondary),
                                        ]),
                                        const SizedBox(height: AppTokens.s2),
                                        Row(children: [
                                          Expanded(
                                              child: Text(
                                                  settingsText(context,
                                                      zh: '${items.length} 个项目',
                                                      en:
                                                          '${items.length} items'),
                                                  style: TextStyle(
                                                      color: secondary,
                                                      fontSize: AppTokens
                                                          .captionFontSize))),
                                          Text(storageFormatBytes(total),
                                              style: TextStyle(
                                                  color: secondary,
                                                  fontSize: AppTokens
                                                      .captionFontSize)),
                                        ]),
                                        const SizedBox(height: AppTokens.s3),
                                        LayoutBuilder(
                                            builder: (context, constraints) {
                                          final size = ((constraints.maxWidth -
                                                      AppTokens.s3 * 3) /
                                                  4)
                                              .clamp(
                                                  0.0, AppTokens.listItemHeight)
                                              .toDouble();
                                          return Row(children: [
                                            for (var i = 0;
                                                i <
                                                    (items.length < 4
                                                        ? items.length
                                                        : 4);
                                                i++) ...[
                                              if (i > 0)
                                                const SizedBox(
                                                    width: AppTokens.s3),
                                              SizedBox(
                                                  width: size,
                                                  height: size,
                                                  child: _StorageThumbnail(
                                                      item: items[i],
                                                      fit: BoxFit.contain)),
                                            ],
                                          ]);
                                        }),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ]),
      children: const [],
    );
  }
}

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
  Timer? _dragTimer;
  Offset? _dragPosition;
  int? _dragAnchor;
  List<StorageMediaItem> _dragItems = [];
  Set<String> _dragBaseline = {};
  bool _dragAdding = true;

  void _endDrag() {
    _dragTimer?.cancel();
    _dragTimer = null;
    _dragPosition = null;
    _dragAnchor = null;
  }

  void _startDrag(StorageMediaItem item, Offset position) {
    if (_deleting) return;
    _endDrag();
    _dragItems = _items;
    _dragAnchor = _dragItems.indexWhere((entry) => entry.id == item.id);
    _dragBaseline = Set.of(_selected);
    _dragAdding = !_selected.contains(item.id);
    _dragPosition = position;
    setState(() {
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
    for (var i = 0; i < _dragItems.length; i++) {
      final box =
          _tileKeys[_dragItems[i].id]?.currentContext?.findRenderObject();
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
        setState(() {
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
    widget.revision.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _endDrag();
    _scrollController.dispose();
    widget.revision.removeListener(_refresh);
    super.dispose();
  }

  List<StorageMediaItem> get _items {
    final rows = widget.source
        .where((item) =>
            item.conversationID == widget.conversationID &&
            (widget.initialType == null || item.type == widget.initialType))
        .toList();
    rows.sort((a, b) =>
        _oldestFirst ? a.time.compareTo(b.time) : b.time.compareTo(a.time));
    return rows;
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
      widget.onRemoved(_selected.toSet());
      if (!mounted) return;
      setState(() {
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

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final items = _items;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisWeek = today.subtract(Duration(days: today.weekday - 1));
    final sections = <String, List<StorageMediaItem>>{};
    for (final item in items) {
      final label = item.time.isAfter(today)
          ? settingsText(context, zh: '今天', en: 'Today')
          : item.time.isAfter(thisWeek)
              ? settingsText(context, zh: '本周', en: 'This week')
              : '${item.time.year}.${item.time.month.toString().padLeft(2, '0')}';
      sections.putIfAbsent(label, () => []).add(item);
    }
    final selectedBytes = items
        .where((item) => _selected.contains(item.id))
        .fold<int>(0, (sum, item) => sum + item.bytes);

    return SettingsScaffold(
      title: _selecting
          ? settingsText(context,
              zh: '已选择 ${_selected.length} 项',
              en: '${_selected.length} selected')
          : settingsText(context, zh: '聊天文件', en: 'Chat Files'),
      leading: _selecting
          ? TextButton(
              onPressed: () => setState(() {
                _selecting = false;
                _selected.clear();
              }),
              child: Text(settingsText(context, zh: '取消', en: 'Cancel')),
            )
          : null,
      actions: [
        TextButton(
          onPressed: () => setState(() {
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
                              '${items.length} 个项目 · ${storageFormatBytes(items.fold<int>(0, (sum, item) => sum + item.bytes))}',
                          en:
                              '${items.length} items · ${storageFormatBytes(items.fold<int>(0, (sum, item) => sum + item.bytes))}'),
                      style: TextStyle(
                          color: AppTokens.textSecondary(dark: dark),
                          fontSize: AppTokens.captionFontSize),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              if (!_selecting)
                TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: AppTokens.textSecondary(dark: dark)),
                    onPressed: () =>
                        setState(() => _oldestFirst = !_oldestFirst),
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
              : ListView(
                  key: _viewportKey,
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                      AppTokens.s4, 0, AppTokens.s4, AppTokens.s6),
                  children: [
                    for (final section in sections.entries) ...[
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppTokens.s4),
                        child: Row(children: [
                          Text(section.key,
                              style: TextStyle(
                                color: AppTokens.textPrimary(dark: dark),
                                fontWeight: FontWeight.w600,
                                fontSize: AppTokens.secondaryFontSize,
                              )),
                          const SizedBox(width: AppTokens.s3),
                          Text('${section.value.length}',
                              style: TextStyle(
                                  color: AppTokens.textSecondary(dark: dark),
                                  fontSize: AppTokens.captionFontSize)),
                        ]),
                      ),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: section.value.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: AppTokens.s3,
                          mainAxisSpacing: AppTokens.s4,
                          childAspectRatio: .84,
                        ),
                        itemBuilder: (context, index) {
                          final item = section.value[index];
                          final selected = _selected.contains(item.id);
                          return GestureDetector(
                            key: _tileKeys.putIfAbsent(
                                item.id, () => GlobalKey()),
                            behavior: HitTestBehavior.opaque,
                            onLongPressStart: (details) =>
                                _startDrag(item, details.globalPosition),
                            onLongPressMoveUpdate: (details) =>
                                _updateDrag(details.globalPosition),
                            onLongPressEnd: (_) => _endDrag(),
                            onLongPressCancel: _endDrag,
                            onTap: () {
                              if (_selecting) {
                                setState(() {
                                  selected
                                      ? _selected.remove(item.id)
                                      : _selected.add(item.id);
                                });
                              } else if (item.type == StorageMediaType.file) {
                                IMUtils.previewFile(item.message);
                              } else {
                                final gallery = items
                                    .where((media) => media.type == item.type)
                                    .toList();
                                final sources = gallery.map((media) {
                                  final message = media.message;
                                  final video =
                                      media.type == StorageMediaType.video;
                                  final localPath = video
                                      ? message.videoElem?.videoPath
                                      : message.pictureElem?.sourcePath;
                                  final availablePath = localPath != null &&
                                          localPath.isNotEmpty &&
                                          File(localPath).existsSync()
                                      ? localPath
                                      : video
                                          ? null
                                          : (media.previewPath ??
                                              (media.localPaths.isNotEmpty
                                                  ? media.localPaths.first
                                                  : null));
                                  return MediaSource(
                                    url: video
                                        ? message.videoElem?.videoUrl
                                        : message
                                            .pictureElem?.sourcePicture?.url,
                                    thumbnail: media.previewPath ??
                                        (video
                                            ? message.videoElem?.snapshotUrl
                                            : message.pictureElem
                                                ?.snapshotPicture?.url) ??
                                        '',
                                    file: availablePath == null
                                        ? null
                                        : File(availablePath),
                                    isVideo: video,
                                    tag: message.clientMsgID,
                                    senderName:
                                        message.senderNickname?.isNotEmpty ==
                                                true
                                            ? message.senderNickname
                                            : message.sendID,
                                    sentAt: media.time,
                                  );
                                }).toList();
                                IMUtils.previewMediaFile(
                                    context: context,
                                    message: item.message,
                                    sources: sources,
                                    initialIndex: gallery.indexWhere(
                                        (media) => media.id == item.id),
                                    showCounter: true);
                              }
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Stack(children: [
                                    Positioned.fill(
                                      child: _StorageThumbnail(item: item),
                                    ),
                                    if (_selecting)
                                      Positioned(
                                        top: AppTokens.s2,
                                        right: AppTokens.s2,
                                        child: Icon(
                                          selected
                                              ? Icons.check_circle_rounded
                                              : Icons
                                                  .radio_button_unchecked_rounded,
                                          color: selected
                                              ? AppTokens.accent
                                              : AppTokens.onAccent,
                                        ),
                                      ),
                                  ]),
                                ),
                                const SizedBox(height: AppTokens.s2),
                                Center(
                                    child: Text(storageFormatBytes(item.bytes),
                                        maxLines: 1,
                                        style: TextStyle(
                                          color: AppTokens.textSecondary(
                                              dark: dark),
                                          fontSize: AppTokens.captionFontSize,
                                        ))),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
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

class _StorageThumbnail extends StatelessWidget {
  const _StorageThumbnail({required this.item, this.fit = BoxFit.cover});

  final StorageMediaItem item;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.rSm),
      child: ColoredBox(
        color: AppTokens.surface(dark: dark),
        child: Stack(fit: StackFit.expand, children: [
          if (item.previewPath != null)
            Image.file(File(item.previewPath!),
                fit: fit,
                cacheWidth: 280,
                errorBuilder: (_, __, ___) => _fileIcon(context))
          else
            _fileIcon(context),
          if (item.type == StorageMediaType.video)
            const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  size: 30, color: AppTokens.onAccent),
            ),
        ]),
      ),
    );
  }

  Widget _fileIcon(BuildContext context) => Center(
        child: Icon(
          item.type == StorageMediaType.file
              ? Icons.insert_drive_file_rounded
              : Icons.image_outlined,
          size: 30,
          color: AppTokens.accent,
        ),
      );
}
