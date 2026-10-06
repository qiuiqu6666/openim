import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_navigation.dart';
import '../widgets/settings_widgets.dart';
import 'storage_media_repository.dart';
import 'storage_widgets.dart';
import '../storage/conversation_storage_page.dart';
import '../storage/widgets/storage_media_thumbnail.dart';

export '../storage/conversation_storage_page.dart';

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
  (int, int, int, int, String, DateTime)? _groupsSignature;
  List<MapEntry<String, List<StorageMediaItem>>> _conversationRows = [];

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

  List<MapEntry<String, List<StorageMediaItem>>> _groupedRows() {
    final now = DateTime.now();
    final signature = (
      _revision.value,
      _tab,
      _minBytes,
      _olderDays,
      _query,
      DateTime(now.year, now.month, now.day),
    );
    if (_groupsSignature == signature) return _conversationRows;
    final query = _query.toLowerCase();
    final groups = <String, List<StorageMediaItem>>{};
    final totals = <String, int>{};
    for (final item in _visibleItems) {
      if (query.isNotEmpty &&
          !item.conversationName.toLowerCase().contains(query)) {
        continue;
      }
      groups.putIfAbsent(item.conversationID, () => []).add(item);
      totals.update(item.conversationID, (value) => value + item.bytes,
          ifAbsent: () => item.bytes);
    }
    _conversationRows = groups.entries.toList()
      ..sort((a, b) => totals[b.key]!.compareTo(totals[a.key]!));
    _groupsSignature = signature;
    return _conversationRows;
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
    final rows = _groupedRows();

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
                                                  child: StorageMediaThumbnail(
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
