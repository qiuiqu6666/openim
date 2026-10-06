import '../../favorites/media/favorite_item_thumbnail.dart';
import '../../favorites/navigation/favorites_app_bar.dart';
import '../../chat/favorites/widgets/favorite_picker_filters.dart';
import '../../chat/favorites/widgets/favorite_picker_item_tile.dart';
import '../../chat/favorites/widgets/favorite_picker_content.dart';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:openim_common/openim_common.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../../services/favorite_repository.dart';
import '../../../services/favorite_send_coordinator.dart';
import '../../favorites/widgets/favorite_capability_gate.dart';
import '../../favorites/widgets/favorite_recovery_banner.dart';
import '../../favorites/widgets/favorite_search_formatter.dart';
import '../../favorites/favorite_p0.dart';
import '../../favorites/media/favorite_picked_media.dart';
import '../settings/settings_navigation.dart';
import '../settings/widgets/settings_widgets.dart';
import 'favorite_note_edit_page.dart';
import 'favorite_detail_page.dart';
import 'favorites_draft_store.dart';

typedef FavoriteItemSender = Future<FavoriteSendResult> Function(FavoriteItem);
typedef FavoriteItemsSender = Future<FavoriteSendResult> Function(
    List<FavoriteItem>);
typedef FavoriteItemsCanceller = Future<void> Function(List<FavoriteItem>);

/// Production uses [repository]. [store] is an explicit legacy draft/demo path.
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({
    super.key,
    this.repository,
    this.onSendToConversation,
    this.onSendItemsToConversation,
    this.onCancelSendItemsToConversation,
    this.store,
  }) : assert((repository == null) != (store == null));

  final FavoriteRepository? repository;
  final FavoriteItemSender? onSendToConversation;
  final FavoriteItemsSender? onSendItemsToConversation;
  final FavoriteItemsCanceller? onCancelSendItemsToConversation;
  final FavoritesDraftStore? store;

  @override
  Widget build(BuildContext context) => repository != null
      ? FavoriteCapabilityGate(
          repository: repository!,
          showScaffold: true,
          child: _CloudFavoritesPage(
              repository: repository!,
              onSendToConversation: onSendToConversation,
              onSendItemsToConversation: onSendItemsToConversation,
              onCancelSendItemsToConversation: onCancelSendItemsToConversation))
      : _FavoritesDraftPage(store: store!);
}

class _FavoritesDraftPage extends StatefulWidget {
  const _FavoritesDraftPage({required this.store});

  final FavoritesDraftStore store;

  @override
  State<_FavoritesDraftPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<_FavoritesDraftPage> {
  bool _picking = false;
  bool _editing = false;
  String _query = '';
  FavoriteDraftType? _filter;
  bool _newestFirst = true;
  final Set<String> _selectedIds = <String>{};

  bool get _isZh => Localizations.localeOf(context).languageCode == 'zh';

  Future<void> _createNote() async {
    final value = await openSettingsPage<String>(
      context,
      const FavoriteNoteEditPage(),
    );
    if (value == null || !mounted) return;
    widget.store.addNote(value);
  }

  Future<void> _pickMedia(FavoriteDraftType type) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: 1,
          requestType: type == FavoriteDraftType.video
              ? RequestType.video
              : RequestType.image,
        ),
      );
      if (!mounted || assets == null || assets.isEmpty) return;
      final bytes = await assets.first.thumbnailDataWithSize(
        const ThumbnailSize(1400, 1400),
        quality: 92,
      );
      if (!mounted || bytes == null || bytes.isEmpty) return;
      widget.store.addMedia(type: type, bytes: Uint8List.fromList(bytes));
    } catch (_) {
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(
          context,
          zh: '无法读取媒体，请检查相册权限后重试',
          en: 'Unable to read media. Check photo permissions and try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _showAddSheet() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(settingsText(context, zh: '添加收藏', en: 'Add Favorite')),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _createNote();
            },
            child: Text(settingsText(context, zh: '笔记', en: 'Note')),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _pickMedia(FavoriteDraftType.image);
            },
            child: Text(settingsText(context, zh: '图片', en: 'Image')),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _pickMedia(FavoriteDraftType.video);
            },
            child: Text(settingsText(context, zh: '视频', en: 'Video')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(settingsText(context, zh: '取消', en: 'Cancel')),
        ),
      ),
    );
  }

  Future<void> _editNote(FavoriteDraftItem item) async {
    final value = await openSettingsPage<String>(
      context,
      FavoriteNoteEditPage(initialText: item.text),
    );
    if (value == null || !mounted) return;
    widget.store.updateNote(item.id, value);
  }

  Future<bool> _confirmDelete({int count = 1}) async {
    return showSettingsConfirm(
      context,
      title: settingsText(context, zh: '删除收藏', en: 'Delete Favorite'),
      message: count > 1
          ? settingsText(
              context,
              zh: '确定删除选中的 $count 条收藏吗？删除后无法恢复。',
              en: 'Delete $count selected favorites? This cannot be undone.',
            )
          : settingsText(
              context,
              zh: '删除后无法恢复，确定删除吗？',
              en: 'This cannot be undone. Delete?',
            ),
      confirmText: settingsText(context, zh: '删除', en: 'Delete'),
      destructive: true,
    );
  }

  Future<void> _deleteOne(FavoriteDraftItem item) async {
    if (!await _confirmDelete() || !mounted) return;
    widget.store.remove(item.id);
    _selectedIds.remove(item.id);
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    if (!await _confirmDelete(count: count) || !mounted) return;
    widget.store.removeMany(_selectedIds);
    setState(() {
      _selectedIds.clear();
      _editing = false;
    });
  }

  void _showItemActions(FavoriteDraftItem item) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          if (item.type == FavoriteDraftType.note)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _editNote(item);
              },
              child: Text(settingsText(context, zh: '编辑', en: 'Edit')),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              _deleteOne(item);
            },
            child: Text(settingsText(context, zh: '删除', en: 'Delete')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(settingsText(context, zh: '取消', en: 'Cancel')),
        ),
      ),
    );
  }

  void _toggleEditing() {
    setState(() {
      _editing = !_editing;
      if (!_editing) _selectedIds.clear();
    });
  }

  void _toggleSelected(FavoriteDraftItem item) {
    setState(() {
      if (!_selectedIds.add(item.id)) {
        _selectedIds.remove(item.id);
      }
    });
  }

  List<FavoriteDraftItem> _visibleItems(List<FavoriteDraftItem> source) {
    final query = _query.trim().toLowerCase();
    final result = source.where((item) {
      if (_filter != null && item.type != _filter) return false;
      if (query.isEmpty) return true;
      final typeLabel = switch (item.type) {
        FavoriteDraftType.note => _isZh ? '文字 笔记' : 'text note',
        FavoriteDraftType.image => _isZh ? '图片' : 'image',
        FavoriteDraftType.video => _isZh ? '视频' : 'video',
      };
      return '${item.text} $typeLabel'.toLowerCase().contains(query);
    }).toList();
    result.sort((a, b) => _newestFirst
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt));
    return result;
  }

  String _groupLabel(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return settingsText(context, zh: '今天', en: 'Today');
    if (day == yesterday) {
      return settingsText(context, zh: '昨天', en: 'Yesterday');
    }
    if (now.difference(day).inDays < 7) {
      const zhWeekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
      const enWeekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ];
      return _isZh
          ? zhWeekdays[local.weekday - 1]
          : enWeekdays[local.weekday - 1];
    }
    return _isZh
        ? '${local.year}年${local.month}月${local.day}日'
        : '${local.month}/${local.day}/${local.year}';
  }

  Map<String, List<FavoriteDraftItem>> _groupByDate(
      List<FavoriteDraftItem> items) {
    final groups = <String, List<FavoriteDraftItem>>{};
    for (final item in items) {
      groups.putIfAbsent(_groupLabel(item.createdAt), () => []).add(item);
    }
    return groups;
  }

  Widget _filterBar(BuildContext context, List<FavoriteDraftItem> items) {
    final dark = settingsIsDark(context);
    final secondary = AppTokens.textSecondary(dark: dark);
    final surface = AppTokens.surface(dark: dark);
    final fill = dark ? const Color(0xFF252A33) : const Color(0xFFF2F4F8);

    Widget chip(FavoriteDraftType? type, String label, IconData? icon) {
      final selected = _filter == type;
      final count = type == null
          ? items.length
          : items.where((e) => e.type == type).length;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(() => _filter = type),
          side: BorderSide.none,
          shape: const StadiumBorder(),
          selectedColor:
              dark ? const Color(0xFF20344D) : const Color(0xFFEAF2FF),
          backgroundColor: fill,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16, color: selected ? AppTokens.accent : secondary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style:
                    TextStyle(color: selected ? AppTokens.accent : secondary),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTokens.accent
                      : (dark
                          ? const Color(0xFF3A404B)
                          : const Color(0xFFE6EBF2)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? Colors.white : secondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Column(
          children: [
            TextField(
              key: const ValueKey('favorites-search'),
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText:
                    settingsText(context, zh: '搜索收藏内容', en: 'Search favorites'),
                prefixIcon: Icon(Icons.search_rounded, color: secondary),
                filled: true,
                fillColor: fill,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        chip(null, settingsText(context, zh: '全部', en: 'All'),
                            null),
                        chip(
                          FavoriteDraftType.note,
                          settingsText(context, zh: '文字', en: 'Text'),
                          Icons.description_rounded,
                        ),
                        chip(
                          FavoriteDraftType.image,
                          settingsText(context, zh: '图片', en: 'Images'),
                          Icons.image_rounded,
                        ),
                        if (items.any((e) => e.type == FavoriteDraftType.video))
                          chip(
                            FavoriteDraftType.video,
                            settingsText(context, zh: '视频', en: 'Videos'),
                            Icons.videocam_rounded,
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('favorites-sort'),
                  tooltip: _newestFirst
                      ? settingsText(context, zh: '最新优先', en: 'Newest first')
                      : settingsText(context, zh: '最早优先', en: 'Oldest first'),
                  onPressed: () => setState(() => _newestFirst = !_newestFirst),
                  icon: Icon(
                    _newestFirst ? Icons.south_rounded : Icons.north_rounded,
                    color: AppTokens.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _groupedChildren(List<FavoriteDraftItem> visible) {
    final dark = settingsIsDark(context);
    final secondary = AppTokens.textSecondary(dark: dark);
    final groups = _groupByDate(visible);
    final children = <Widget>[];
    for (final entry in groups.entries) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            entry.key,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: secondary,
            ),
          ),
        ),
      );
      for (final item in entry.value) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Dismissible(
              key: ValueKey('favorite-${item.id}'),
              direction: _editing
                  ? DismissDirection.none
                  : DismissDirection.endToStart,
              confirmDismiss: (_) => _confirmDelete(),
              onDismissed: (_) => widget.store.remove(item.id),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFFE64340),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              child: _FavoriteDraftTile(
                item: item,
                editing: _editing,
                selected: _selectedIds.contains(item.id),
                onTap: () {
                  if (_editing) {
                    _toggleSelected(item);
                  } else if (item.type == FavoriteDraftType.note) {
                    _editNote(item);
                  } else {
                    _showItemActions(item);
                  }
                },
                onLongPress: _editing ? null : () => _showItemActions(item),
              ),
            ),
          ),
        );
      }
    }
    children.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
        child: Column(
          children: [
            SettingsEmptyState(
              icon: Icons.bookmark_border_rounded,
              title: groups.isEmpty
                  ? settingsText(context,
                      zh: '没有匹配的收藏', en: 'No matching favorites')
                  : settingsText(context, zh: '没有更多了', en: 'No more favorites'),
            ),
            Text(
              settingsText(context, zh: '已显示全部收藏内容', en: 'All favorites shown'),
              style: TextStyle(fontSize: 13, color: secondary),
            ),
          ],
        ),
      ),
    );
    return children;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final dark = settingsIsDark(context);
          final items = widget.store.items;
          final visible = _visibleItems(items);
          return Scaffold(
            backgroundColor: AppTokens.background(dark: dark),
            appBar: favoritesAppBar(
              context,
              title: settingsText(context, zh: '收藏', en: 'Favorites'),
              actionLabel: items.isEmpty
                  ? null
                  : _editing
                      ? settingsText(context, zh: '完成', en: 'Done')
                      : settingsText(context, zh: '编辑', en: 'Edit'),
              onAction: _toggleEditing,
            ),
            body: Column(
              children: [
                _filterBar(context, items),
                Expanded(
                  child: items.isEmpty
                      ? Column(
                          children: [
                            Expanded(
                              child: SettingsEmptyState(
                                icon: Icons.bookmark_border_rounded,
                                title: settingsText(context,
                                    zh: '暂无收藏', en: 'No favorites yet'),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _picking ? null : _showAddSheet,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTokens.accent,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                  ),
                                  child: Text(settingsText(context,
                                      zh: '添加收藏', en: 'Add Favorite')),
                                ),
                              ),
                            ),
                          ],
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            await Future<void>.delayed(
                                const Duration(milliseconds: 120));
                          },
                          child: ListView(
                            key: const ValueKey('favorites-list'),
                            padding: const EdgeInsets.only(bottom: 88),
                            children: _groupedChildren(visible),
                          ),
                        ),
                ),
              ],
            ),
            floatingActionButton: items.isEmpty || _editing
                ? null
                : FloatingActionButton(
                    key: const ValueKey('favorites-add-fab'),
                    onPressed: _picking ? null : _showAddSheet,
                    backgroundColor: AppTokens.accent,
                    shape: const CircleBorder(),
                    child: _picking
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.add, color: Colors.white, size: 32),
                  ),
            bottomNavigationBar: _editing
                ? SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const ValueKey('favorites-delete-selected'),
                          onPressed:
                              _selectedIds.isEmpty ? null : _deleteSelected,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE64340),
                            disabledBackgroundColor:
                                AppTokens.border(dark: dark),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            _selectedIds.isEmpty
                                ? settingsText(context, zh: '删除', en: 'Delete')
                                : settingsText(
                                    context,
                                    zh: '删除(${_selectedIds.length})',
                                    en: 'Delete (${_selectedIds.length})',
                                  ),
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
          );
        },
      );
}

class _FavoriteDraftTile extends StatelessWidget {
  const _FavoriteDraftTile({
    required this.item,
    required this.editing,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final FavoriteDraftItem item;
  final bool editing;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  String _timeLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _preview(bool dark) {
    if (item.type == FavoriteDraftType.note) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF20344D) : const Color(0xFFECF2FF),
          borderRadius: BorderRadius.circular(9),
        ),
        child:
            const Icon(Icons.title_rounded, size: 27, color: Color(0xFF568EFF)),
      );
    }
    final bytes = item.bytes;
    return SizedBox.square(
      dimension: 60,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null && bytes.isNotEmpty)
              Image.memory(bytes, fit: BoxFit.cover)
            else
              ColoredBox(
                color: dark ? const Color(0xFF292D35) : const Color(0xFFF2F4F8),
                child: const Icon(Icons.image_outlined),
              ),
            if (item.type == FavoriteDraftType.video)
              const Align(
                alignment: Alignment.center,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: Colors.black45, shape: BoxShape.circle),
                  child: Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final primary = AppTokens.textPrimary(dark: dark);
    final secondary = AppTokens.textSecondary(dark: dark);
    final surface = AppTokens.surface(dark: dark);
    final typeText = switch (item.type) {
      FavoriteDraftType.note =>
        settingsText(context, zh: '文字收藏', en: 'Text favorite'),
      FavoriteDraftType.image =>
        settingsText(context, zh: '图片收藏', en: 'Image favorite'),
      FavoriteDraftType.video =>
        settingsText(context, zh: '视频收藏', en: 'Video favorite'),
    };

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (editing) ...[
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? AppTokens.accent : secondary,
                  size: 22,
                ),
                const SizedBox(width: 12),
              ],
              _preview(dark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.type == FavoriteDraftType.note &&
                                    item.text.trim().isNotEmpty
                                ? item.text.trim()
                                : typeText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeLabel(item.createdAt),
                          style: TextStyle(color: secondary, fontSize: 11),
                        ),
                        if (!editing)
                          Icon(Icons.chevron_right_rounded,
                              size: 22, color: secondary),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(typeText,
                        style: TextStyle(color: secondary, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _FavoriteCreateAction { note, image, video, audio, file, link }

class _CloudFavoritesPage extends StatefulWidget {
  const _CloudFavoritesPage({
    required this.repository,
    this.onSendToConversation,
    this.onSendItemsToConversation,
    this.onCancelSendItemsToConversation,
  });

  final FavoriteRepository repository;
  final FavoriteItemSender? onSendToConversation;
  final FavoriteItemsSender? onSendItemsToConversation;
  final FavoriteItemsCanceller? onCancelSendItemsToConversation;

  @override
  State<_CloudFavoritesPage> createState() => _CloudFavoritesPageState();
}

class _CloudFavoritesPageState extends State<_CloudFavoritesPage> {
  bool _editing = false;
  bool _busy = false;
  bool _choosingCreateAction = false;
  bool _confirmingDelete = false;
  final Set<String> _selectedIds = {};
  final Map<String, FavoriteItem> _selectedItems = {};
  final Map<String, int> _unconfirmedDeleteVersions = {};
  String? _batchMessage;
  late final String _scope;
  bool _invalid = false;
  bool get _current => !_invalid && widget.repository.isSessionCurrent(_scope);

  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
    widget.repository.addListener(_checkSession);
  }

  void _checkSession() {
    if (mounted && !_invalid && !_current) {
      setState(() {
        _invalid = true;
        _selectedIds.clear();
        _selectedItems.clear();
      });
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_checkSession);
    super.dispose();
  }

  String _text(String zh, String en) => settingsText(context, zh: zh, en: en);

  Future<void> _openDetail(FavoriteItem item) async {
    if (_busy || !_current) return;
    if (_editing) {
      setState(() {
        if (!_selectedIds.add(item.id)) {
          _selectedIds.remove(item.id);
          _selectedItems.remove(item.id);
        } else {
          _selectedItems[item.id] = item;
        }
        _batchMessage = null;
      });
      return;
    }
    await openSettingsPage<void>(
      context,
      FavoriteDetailPage(
        repository: widget.repository,
        item: item,
        onSend: widget.onSendToConversation,
        onCancelSend: widget.onCancelSendItemsToConversation == null
            ? null
            : (item) => widget.onCancelSendItemsToConversation!([item]),
      ),
    );
  }

  Future<void> _itemActions(FavoriteItem item) async {
    if (_busy || _editing || !_current) return;
    final action = await showSettingsActionSheet<String>(context,
        title: item.title,
        actions: [
          SettingsAction(_text('查看详情', 'View details'), 'detail'),
          if (widget.onSendToConversation != null && canSendFavoriteP0(item))
            SettingsAction(_text('发送到对话', 'Send to a chat'), 'send'),
          SettingsAction(_text('删除', 'Delete'), 'delete', destructive: true),
        ]);
    if (!mounted || action == null || !_current) return;
    if (action == 'detail') {
      await _openDetail(item);
    } else if (action == 'send') {
      setState(() => _busy = true);
      try {
        await widget.repository.requireAvailable();
        if (!mounted || !_current) return;
        final result = await widget.onSendToConversation!(item);
        if (mounted &&
            _current &&
            result.errorCode == 'BATCH_RESELECT_REQUIRED') {
          await widget.repository.refresh();
        }
        if (mounted && _current && result.errorCode != 'CANCELLED') {
          showSettingsMessage(
              context,
              result.status == FavoriteSendStatus.success
                  ? _text('已发送', 'Sent')
                  : result.errorMessage ??
                      _text('发送未完成，请重试', 'Could not send. Please retry.'));
        }
      } catch (error) {
        if (mounted && _current) {
          showSettingsError(context, error, _text('发送失败', 'Could not send'));
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      await _deleteItems([item]);
    }
  }

  Future<void> _deleteItems(List<FavoriteItem> items) async {
    if (_busy || items.isEmpty || !_current) return;
    if (items.length > 100) {
      showSettingsMessage(context,
          _text('每次最多删除 100 条收藏', 'Delete up to 100 favorites at a time.'));
      return;
    }
    setState(() => _busy = true);
    final failed = <String>{};
    final conflicts = <String, FavoriteItem>{};
    String? failureMessage;
    var submitted = false;
    try {
      await widget.repository.requireAvailable();
      if (!_current) return;
      final snapshot = <FavoriteItem>[];
      for (final item in items) {
        final rejectedVersion = _unconfirmedDeleteVersions[item.id];
        if (rejectedVersion == null) {
          snapshot.add(item);
          continue;
        }
        final latest = await widget.repository.getDetail(item.id);
        if (!mounted || !_current) return;
        if (latest.id != item.id || latest.version == rejectedVersion) {
          throw const FavoriteApiException(20061, '最新版本尚未核实，请刷新后重试');
        }
        _unconfirmedDeleteVersions.remove(item.id);
        if (_selectedItems.containsKey(item.id)) {
          setState(() => _selectedItems[item.id] = latest);
        }
        snapshot.add(latest);
        conflicts[item.id] = latest;
      }
      items = snapshot;
      if (!mounted || !_current) return;
      setState(() => _confirmingDelete = true);
      final confirmed = await showSettingsConfirm(context,
          title: _text('删除收藏', 'Delete favorites'),
          message: _text('确定删除这 ${items.length} 条收藏吗？已发送的聊天消息会保留。',
              'Delete ${items.length} favorites? Messages already sent will be kept.'),
          confirmText: _text('删除', 'Delete'),
          destructive: true);
      if (!mounted || !confirmed || !_current) return;
      setState(() => _confirmingDelete = false);
      submitted = true;
      if (items.length == 1) {
        final item = items.single;
        await widget.repository.delete(item.id, expectedVersion: item.version);
      } else {
        final result = await widget.repository.deleteMany(items);
        for (final item in result.conflicts) {
          failed.add(item.id);
          if (item.currentItem != null) {
            conflicts[item.id] = item.currentItem!;
            _unconfirmedDeleteVersions.remove(item.id);
          } else {
            _unconfirmedDeleteVersions[item.id] =
                items.firstWhere((selected) => selected.id == item.id).version;
          }
        }
      }
    } catch (error) {
      failed.addAll(items.map((item) => item.id));
      if (error is FavoriteApiException) {
        failureMessage = error.message;
        if (submitted && error.isVersionConflict && items.length == 1) {
          final item = items.single;
          _unconfirmedDeleteVersions[item.id] = item.version;
          FavoriteItem? latest = error.currentItem;
          if (latest == null) {
            try {
              latest = await widget.repository.getDetail(item.id);
            } catch (_) {
              /* A later user action must re-read before deleting. */
            }
          }
          if (_current &&
              latest?.id == item.id &&
              latest!.version != item.version) {
            conflicts[item.id] = latest;
            _unconfirmedDeleteVersions.remove(item.id);
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirmingDelete = false;
        });
      }
    }
    if (!mounted || !_current) return;
    setState(() {
      if (submitted || failed.isNotEmpty) {
        _selectedIds
          ..clear()
          ..addAll(failed);
        _selectedItems
          ..clear()
          ..addEntries(items
              .where((item) => failed.contains(item.id))
              .map((item) => MapEntry(item.id, conflicts[item.id] ?? item)));
        _editing = failed.isNotEmpty;
      }
    });
    if (failed.isNotEmpty) {
      showSettingsMessage(
          context,
          failureMessage ??
              _text('${failed.length} 条内容已更新或删除失败，请检查后重试',
                  '${failed.length} items could not be deleted. Please retry.'));
    }
  }

  Future<void> _sendSelected() async {
    if (_busy ||
        !_current ||
        _selectedItems.isEmpty ||
        widget.onSendItemsToConversation == null) {
      return;
    }
    final items = List<FavoriteItem>.of(_selectedItems.values);
    if (items.any((item) => !canSendFavoriteP0(item))) {
      showSettingsMessage(
          context,
          _text('请选择已保存且支持发送的收藏',
              'Select saved favorites that support sending.'));
      return;
    }
    setState(() {
      _busy = true;
      _batchMessage = null;
    });
    try {
      await widget.repository.requireAvailable();
      if (!mounted || !_current) return;
      final result = await widget.onSendItemsToConversation!(items);
      if (!mounted || !_current || result.errorCode == 'CANCELLED') return;
      if (result.errorCode == 'BATCH_RESELECT_REQUIRED') {
        await widget.repository.refresh();
        if (mounted && _current) {
          setState(() {
            _selectedIds.clear();
            _selectedItems.clear();
            _editing = false;
            _batchMessage = result.errorMessage ??
                _text('收藏内容已更新，请重新选择收藏与发送目标',
                    'Favorites have changed. Select favorites and a destination again.');
          });
        }
        return;
      }
      if (result.status == FavoriteSendStatus.success) {
        setState(() {
          _selectedIds.clear();
          _selectedItems.clear();
          _editing = false;
        });
        showSettingsMessage(context, _text('已发送', 'Sent'));
      } else {
        setState(() => _batchMessage = result.status ==
                FavoriteSendStatus.unknown
            ? _text('发送状态待确认，请查看目标对话。保留选择以继续此批次。',
                'Sending status is unconfirmed. Check the destination chat. Keep the selection to continue this batch.')
            : '${result.errorMessage ?? _text('发送未完成', 'Sending incomplete')}\n${_text('已完成 ${result.sentCount}/${result.totalCount} 项发送。再次点击发送继续未完成部分。', 'Completed ${result.sentCount}/${result.totalCount} sends. Tap send again to continue the remaining sends.')}');
      }
    } catch (error) {
      if (mounted && _current) {
        setState(() => _batchMessage = error is FavoriteApiException
            ? error.message
            : _text('发送失败，请重试', 'Could not send. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelSelectedSend() async {
    if (_busy ||
        !_current ||
        _selectedItems.isEmpty ||
        _batchMessage == null ||
        widget.onCancelSendItemsToConversation == null) {
      return;
    }
    final items = List<FavoriteItem>.of(_selectedItems.values);
    final confirmed = await confirmCancelFavoriteSend(context);
    if (!mounted || !_current || !confirmed) return;
    setState(() => _busy = true);
    try {
      await widget.onCancelSendItemsToConversation!(items);
      if (mounted && _current) {
        setState(() {
          _selectedIds.clear();
          _selectedItems.clear();
          _editing = false;
          _batchMessage = null;
        });
      }
    } catch (error) {
      if (mounted && _current) {
        setState(() => _batchMessage = error is FavoriteApiException
            ? error.message
            : _text('取消失败，请重试', 'Could not cancel. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFavorite() async {
    if (_busy ||
        _choosingCreateAction ||
        widget.repository.saving ||
        !_current) {
      return;
    }
    _choosingCreateAction = true;
    _FavoriteCreateAction? action;
    try {
      action = await showSettingsActionSheet<_FavoriteCreateAction>(context,
          title: _text('添加收藏', 'Add favorite'),
          actions: [
            SettingsAction(_text('笔记', 'Note'), _FavoriteCreateAction.note),
            SettingsAction(_text('图片', 'Image'), _FavoriteCreateAction.image),
            SettingsAction(_text('视频', 'Video'), _FavoriteCreateAction.video),
            SettingsAction(_text('音频', 'Audio'), _FavoriteCreateAction.audio),
            SettingsAction(_text('文件', 'File'), _FavoriteCreateAction.file),
            SettingsAction(_text('链接', 'Link'), _FavoriteCreateAction.link),
          ]);
    } finally {
      _choosingCreateAction = false;
    }
    if (!mounted || action == null || !_current) return;
    if (action == _FavoriteCreateAction.note) {
      await openSettingsPage<String>(
          context,
          FavoriteNoteEditPage(
              repository: widget.repository,
              onSave: (text) async {
                if (!_current) throw StateError('登录状态已改变');
                await widget.repository.createNote(text);
              }));
      return;
    }
    if (action == _FavoriteCreateAction.link) {
      await showDialog<void>(
          context: context,
          builder: (_) => _FavoriteValueDialog(
              title: _text('添加链接', 'Add link'),
              label: _text('网页地址', 'Web address'),
              hint: 'https://',
              onSave: (value) async {
                if (!_current) throw StateError('登录状态已改变');
                await widget.repository.createLink(value);
              }));
      return;
    }
    setState(() => _busy = true);
    try {
      String? path;
      String? name;
      String? reportedMimeType;
      final kind = switch (action) {
        _FavoriteCreateAction.image => FavoriteKind.image,
        _FavoriteCreateAction.video => FavoriteKind.video,
        _FavoriteCreateAction.audio => FavoriteKind.audio,
        _ => FavoriteKind.file,
      };
      if (kind == FavoriteKind.image || kind == FavoriteKind.video) {
        final assets = await AssetPicker.pickAssets(context,
            pickerConfig: AssetPickerConfig(
                maxAssets: 1,
                requestType: kind == FavoriteKind.video
                    ? RequestType.video
                    : RequestType.image));
        if (!mounted || !_current || assets == null || assets.isEmpty) return;
        // originFile preserves the actual video/image, never just its thumbnail.
        final original = await assets.first.originFile;
        if (original == null) throw StateError('无法读取媒体原件');
        path = original.path;
        name = original.uri.pathSegments.last;
        reportedMimeType = await assets.first.mimeTypeAsync;
      } else {
        final selection = await FilePicker.platform.pickFiles(
            type: kind == FavoriteKind.audio ? FileType.audio : FileType.any,
            allowMultiple: false,
            withData: false);
        if (!mounted ||
            !_current ||
            selection == null ||
            selection.files.isEmpty) {
          return;
        }
        path = selection.files.first.path;
        name = selection.files.first.name;
      }
      if (!mounted || !_current) return;
      if (path == null || path.isEmpty) {
        throw const FavoriteApiException(
            'ORIGINAL_UNAVAILABLE', '无法读取所选原件，请重新选择');
      }
      final selected = await FavoritePickedMedia.inspect(path,
          kind: kind, fileName: name, reportedMimeType: reportedMimeType);
      if (!mounted || !_current) return;
      final item = await widget.repository.createMedia(
          kind: kind,
          filePath: selected.filePath,
          fileName: selected.fileName,
          mimeType: selected.mimeType);
      if (mounted && _current) {
        showSettingsMessage(
            context,
            item.isReady
                ? _text('已收藏', 'Saved')
                : _text(
                    '正在保存，完成后即可发送', 'Saving. You can send when it is ready.'));
      }
    } catch (error) {
      if (mounted && _current) {
        showSettingsError(
            context, error, _text('收藏失败，请重试', 'Could not save. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return Scaffold(
      backgroundColor: AppTokens.background(dark: dark),
      appBar: favoritesAppBar(
        context,
        title: _text('收藏', 'Favorites'),
        actionLabel: _editing ? _text('完成', 'Done') : _text('编辑', 'Edit'),
        onAction: _busy || !_current
            ? null
            : () => setState(() {
                  _editing = !_editing;
                  _selectedIds.clear();
                  _selectedItems.clear();
                  _batchMessage = null;
                }),
      ),
      body: SafeArea(
        top: false,
        child: _invalid
            ? SettingsEmptyState(
                icon: Icons.lock_outline,
                title: _text('登录状态已改变，请重新打开收藏',
                    'Your account changed. Reopen favorites.'))
            : Column(children: [
                FavoriteRecoveryBanner(repository: widget.repository),
                if (_busy && !_confirmingDelete)
                  AnimatedBuilder(
                      animation: widget.repository,
                      builder: (context, _) => Column(children: [
                            LinearProgressIndicator(
                                value: widget.repository.uploadProgress),
                            if (widget.repository.uploadProgress != null)
                              Padding(
                                  padding: const EdgeInsets.all(AppTokens.s3),
                                  child: Text(_text(
                                      '正在上传原件 ${(widget.repository.uploadProgress! * 100).round()}%',
                                      'Uploading original ${(widget.repository.uploadProgress! * 100).round()}%'))),
                          ])),
                if (_batchMessage != null)
                  Padding(
                      padding: const EdgeInsets.all(AppTokens.s4),
                      child: Semantics(
                          liveRegion: true,
                          child: Text(_batchMessage!,
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.error)))),
                if (_batchMessage != null &&
                    _selectedItems.isNotEmpty &&
                    widget.onCancelSendItemsToConversation != null)
                  TextButton.icon(
                      key: const ValueKey('favorites-cancel-send'),
                      onPressed: _busy ? null : _cancelSelectedSend,
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(_text('取消剩余发送', 'Cancel remaining sends'))),
                Expanded(
                    key: const ValueKey('favorites-cloud-collection'),
                    child: FavoriteCollectionView(
                      repository: widget.repository,
                      selectedIds: _selectedIds,
                      selectionMode: _editing,
                      disabled: _busy,
                      onTap: _openDetail,
                      onLongPress: _itemActions,
                      emptyActionLabel: _text('添加收藏', 'Add favorite'),
                      onEmptyAction: _addFavorite,
                    )),
                if (_editing)
                  Padding(
                    padding: const EdgeInsets.all(AppTokens.s5),
                    child: Wrap(
                        spacing: AppTokens.s3,
                        runSpacing: AppTokens.s3,
                        children: [
                          if (widget.onSendItemsToConversation != null)
                            FilledButton.icon(
                                key: const ValueKey('favorites-send-selected'),
                                onPressed: _busy || _selectedIds.isEmpty
                                    ? null
                                    : _sendSelected,
                                icon: const Icon(Icons.send_outlined),
                                label: Text(_text('发送 (${_selectedIds.length})',
                                    'Send (${_selectedIds.length})'))),
                          OutlinedButton.icon(
                            key: const ValueKey('favorites-delete-selected'),
                            onPressed: _busy || _selectedIds.isEmpty
                                ? null
                                : () => _deleteItems(
                                    _selectedItems.values.toList()),
                            icon: const Icon(Icons.delete_outline),
                            label: Text(_text('删除 (${_selectedIds.length})',
                                'Delete (${_selectedIds.length})')),
                          ),
                        ]),
                  ),
              ]),
      ),
      floatingActionButton: _editing
          ? null
          : FloatingActionButton(
              key: const ValueKey('favorites-add-fab'),
              tooltip: _text('添加收藏', 'Add favorite'),
              onPressed: _busy || _invalid ? null : _addFavorite,
              backgroundColor: AppTokens.accent,
              foregroundColor: AppTokens.onAccent,
              child: const Icon(Icons.add),
            ),
    );
  }
}

/// One pageable, searchable collection surface for management and chat sending.
class FavoriteCollectionView extends StatefulWidget {
  const FavoriteCollectionView({
    super.key,
    required this.repository,
    required this.onTap,
    this.onLongPress,
    this.trailingBuilder,
    this.selectedIds = const {},
    this.selectionMode = false,
    this.disabled = false,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.pickerStyle = false,
    this.onManage,
  });

  final FavoriteRepository repository;
  final void Function(FavoriteItem) onTap;
  final void Function(FavoriteItem)? onLongPress;
  final Widget Function(FavoriteItem)? trailingBuilder;
  final Set<String> selectedIds;
  final bool selectionMode;
  final bool disabled;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final bool pickerStyle;
  final VoidCallback? onManage;

  @override
  State<FavoriteCollectionView> createState() => _FavoriteCollectionViewState();
}

class _FavoriteCollectionViewState extends State<FavoriteCollectionView> {
  late final TextEditingController _search;
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;
  FavoriteKind? _kind;
  bool _searching = false;
  List<FavoriteItem> _pickerItems = const [];
  bool _pickerHasMore = false;

  String _text(String zh, String en) => settingsText(context, zh: zh, en: en);

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
        text: widget.pickerStyle
            ? ''
            : FavoriteSearchFormatter.limit(widget.repository.query));
    _kind = !widget.pickerStyle &&
            favoriteP0Kinds.contains(widget.repository.filterKind)
        ? widget.repository.filterKind
        : null;
    _scroll.addListener(_loadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_refresh());
      }
    });
  }

  Future<void> _refresh() => widget.repository.refresh(
      query: FavoriteSearchFormatter.limit(_search.text.trim()), kind: _kind);

  void _loadMore() {
    if (!widget.disabled &&
        _scroll.hasClients &&
        _scroll.position.extentAfter < 240 &&
        widget.repository.hasMore &&
        !widget.repository.loadingMore &&
        !widget.repository.loading &&
        widget.repository.error == null) {
      unawaited(_loadNextPage());
    }
  }

  Future<void> _loadNextPage() async {
    try {
      await widget.repository.loadMore();
    } catch (error) {
      if (mounted) {
        showSettingsError(
            context, error, _text('加载失败，请重试', 'Could not load. Please retry.'));
      }
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
        unawaited(_refresh());
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll
      ..removeListener(_loadMore)
      ..dispose();
    super.dispose();
  }

  Widget _filters() {
    final dark = settingsIsDark(context);
    if (widget.pickerStyle) {
      return FavoritePickerFilters(
        search: _search,
        searching: _searching,
        onToggleSearch: () {
          _debounce?.cancel();
          setState(() => _searching = !_searching);
          if (!_searching) {
            _search.clear();
            unawaited(_refresh());
          }
        },
        onChanged: _searchChanged,
        onSubmitted: () {
          _debounce?.cancel();
          unawaited(_refresh());
        },
        kind: _kind,
        onKind: (kind) {
          _debounce?.cancel();
          setState(() => _kind = kind);
          if (_scroll.hasClients) _scroll.jumpTo(0);
          unawaited(_refresh());
        },
        items: _pickerItems,
        hasMore: _pickerHasMore,
        disabled: widget.disabled,
        onManage: widget.onManage,
      );
    }
    return ColoredBox(
      color: AppTokens.surface(dark: dark),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s4),
        child: Column(children: [
          TextField(
            key: const ValueKey('favorites-search'),
            controller: _search,
            inputFormatters: const [FavoriteSearchFormatter()],
            enabled: !widget.disabled,
            onChanged: _searchChanged,
            onSubmitted: (_) {
              _debounce?.cancel();
              unawaited(_refresh());
            },
            decoration: InputDecoration(
              labelText: _text('搜索收藏内容', 'Search favorites'),
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: AppTokens.surfaceAlt(dark: dark),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTokens.rLg),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: AppTokens.s3),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final kind in <FavoriteKind?>[
                null,
                ...favoriteP0Kinds,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: AppTokens.s3),
                  child: ChoiceChip(
                    key: ValueKey('favorite-filter-${kind?.name ?? 'all'}'),
                    label: Text(kind == null
                        ? _text('全部', 'All')
                        : favoriteKindLabel(context, kind)),
                    selected: _kind == kind,
                    showCheckmark: false,
                    onSelected: widget.disabled
                        ? null
                        : (_) {
                            _debounce?.cancel();
                            setState(() => _kind = kind);
                            if (_scroll.hasClients) _scroll.jumpTo(0);
                            unawaited(_refresh());
                          },
                    side: BorderSide.none,
                    selectedColor: AppTokens.accent.withValues(alpha: 0.14),
                    backgroundColor: AppTokens.surfaceAlt(dark: dark),
                    labelStyle: TextStyle(
                        color: _kind == kind
                            ? AppTokens.accent
                            : AppTokens.textSecondary(dark: dark)),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  String _date(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }

  Widget _footer(FavoriteRepository repository) {
    if (repository.loadingMore) {
      return const Padding(
          padding: EdgeInsets.all(AppTokens.s5),
          child: Center(child: CircularProgressIndicator()));
    }
    if (repository.hasMore) {
      return TextButton(
        key: const ValueKey('favorites-load-more'),
        onPressed: widget.disabled ? null : _loadNextPage,
        child: Text(_text('加载更多', 'Load more')),
      );
    }
    return Padding(
      padding: EdgeInsets.all(widget.pickerStyle ? AppTokens.s5 : AppTokens.s6),
      child: Text(
          widget.pickerStyle
              ? _text(
                  '—  ${_pickerHasMore ? '已加载' : '已收藏'} ${_pickerItems.length} 条内容  —',
                  '—  ${_pickerItems.length} ${_pickerHasMore ? 'loaded' : 'saved'} items  —')
              : _text('已显示全部收藏', 'All favorites shown'),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: settingsSecondaryTextColor(context)
                  .withValues(alpha: widget.pickerStyle ? .72 : 1),
              fontSize: widget.pickerStyle
                  ? FavoritePickerTokens.footerFontSize
                  : null)),
    );
  }

  Widget _content(
      FavoriteRepository repository, List<FavoriteItem> items, Widget list) {
    if (widget.pickerStyle) {
      return FavoritePickerContent(
        revision: (
          repository.query,
          repository.filterKind,
          items.isEmpty,
          repository.error
        ),
        loading: repository.loading,
        child: list,
      );
    }
    return repository.loading && items.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : list;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.repository,
        builder: (context, _) {
          final repository = widget.repository;
          final items = repository.items;
          if (widget.pickerStyle &&
              !repository.loading &&
              repository.error == null &&
              repository.query.isEmpty &&
              repository.filterKind == null) {
            _pickerItems = List.of(items);
            _pickerHasMore = repository.hasMore;
          }
          return LayoutBuilder(builder: (context, constraints) {
            final compact = widget.pickerStyle &&
                constraints.maxHeight <
                    FavoritePickerTokens.compactControlsHeight;
            return Column(children: [
              if (compact)
                Flexible(child: SingleChildScrollView(child: _filters()))
              else
                _filters(),
              if (!widget.pickerStyle && repository.loading && items.isNotEmpty)
                const LinearProgressIndicator(),
              if (repository.isCached)
                Padding(
                    padding: const EdgeInsets.all(AppTokens.s3),
                    child: Text(
                        _text('显示已缓存收藏，正在同步',
                            'Showing cached favorites while syncing'),
                        style: TextStyle(
                            color: settingsSecondaryTextColor(context)))),
              if (repository.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
                  child: Row(children: [
                    Expanded(
                        child: Semantics(
                            liveRegion: true,
                            child: Text(repository.error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)))),
                    TextButton(
                        onPressed: widget.disabled ? null : _refresh,
                        child: Text(_text('重试', 'Retry'))),
                  ]),
                ),
              Flexible(
                flex: compact ? 2 : 1,
                fit: FlexFit.tight,
                child: _content(
                  repository,
                  items,
                  RefreshIndicator(
                    onRefresh: widget.disabled ? () async {} : _refresh,
                    child: ListView.builder(
                      key: const ValueKey('favorites-list'),
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(
                          bottom: widget.pickerStyle ? 0 : AppTokens.s8 * 3),
                      itemCount: items.isEmpty
                          ? 1
                          : items.length + (widget.pickerStyle ? 0 : 1),
                      itemBuilder: (context, index) {
                        if (items.isEmpty) {
                          if (widget.pickerStyle && repository.loading) {
                            return const SizedBox.shrink();
                          }
                          return SettingsEmptyState(
                            icon: repository.error != null
                                ? Icons.cloud_off_outlined
                                : Icons.bookmark_border_rounded,
                            title: repository.error != null
                                ? _text('收藏加载失败', 'Could not load favorites')
                                : _search.text.isNotEmpty || _kind != null
                                    ? _text('没有匹配的收藏', 'No matching favorites')
                                    : _text('暂无收藏', 'No favorites yet'),
                            description: repository.error != null
                                ? _text('检查网络后重试',
                                    'Check your connection and retry')
                                : _text('长按聊天消息即可收藏，也可以添加笔记或文件',
                                    'Save a message with a long press, or add a note or file'),
                            actionLabel: repository.error != null
                                ? _text('重试', 'Retry')
                                : widget.emptyActionLabel,
                            onAction: widget.disabled
                                ? null
                                : repository.error != null
                                    ? _refresh
                                    : widget.onEmptyAction,
                          );
                        }
                        if (index == items.length) {
                          return _footer(repository);
                        }
                        final item = items[index];
                        if (widget.pickerStyle) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(
                                FavoritePickerTokens.listPadding,
                                0,
                                FavoritePickerTokens.listPadding,
                                FavoritePickerTokens.cardGap),
                            child: FavoritePickerItemTile(
                              key: ValueKey('favorite-${item.id}'),
                              item: item,
                              repository: repository,
                              onTap: widget.disabled
                                  ? null
                                  : () => widget.onTap(item),
                              trailing: widget.trailingBuilder?.call(item),
                            ),
                          );
                        }
                        final date = _date(item.createdAt);
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(
                              AppTokens.s4, 0, AppTokens.s4, AppTokens.s4),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (date.isNotEmpty &&
                                    (index == 0 ||
                                        date !=
                                            _date(items[index - 1].createdAt)))
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: AppTokens.s4,
                                          horizontal: AppTokens.s3),
                                      child: Text(date,
                                          style: TextStyle(
                                              color: settingsSecondaryTextColor(
                                                  context)))),
                                FavoriteItemTile(
                                  key: ValueKey('favorite-${item.id}'),
                                  item: item,
                                  repository: widget.repository,
                                  selected:
                                      widget.selectedIds.contains(item.id),
                                  selectionMode: widget.selectionMode,
                                  onTap: widget.disabled
                                      ? null
                                      : () => widget.onTap(item),
                                  onLongPress: widget.disabled ||
                                          widget.onLongPress == null
                                      ? null
                                      : () => widget.onLongPress!(item),
                                  trailing: widget.trailingBuilder?.call(item),
                                ),
                              ]),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (widget.pickerStyle && !compact)
                SizedBox(
                  key: const ValueKey('favorites-picker-footer'),
                  height: FavoritePickerTokens.footerHeight *
                      MediaQuery.textScalerOf(context)
                          .scale(FavoritePickerTokens.footerFontSize) /
                      FavoritePickerTokens.footerFontSize,
                  child: Center(
                    child: repository.loading && _pickerItems.isEmpty
                        ? Text(_text('正在加载收藏', 'Loading favorites'),
                            style: TextStyle(
                              fontSize: FavoritePickerTokens.footerFontSize,
                              color: settingsSecondaryTextColor(context),
                            ))
                        : _footer(repository),
                  ),
                ),
            ]);
          });
        },
      );
}

Future<bool> confirmCancelFavoriteSend(BuildContext context) => showSettingsConfirm(
    context,
    title: settingsText(context, zh: '取消剩余发送', en: 'Cancel remaining sends'),
    message: settingsText(context,
        zh: '取消不会撤回已发消息。再次发送会作为新操作，可能再次发送已成功项。发送状态待确认的消息仍需先核实。',
        en:
            'Canceling will not recall sent messages. Sending again starts a new operation and may resend successful items. Messages with an unconfirmed status still need verification.'),
    confirmText:
        settingsText(context, zh: '取消剩余发送', en: 'Cancel remaining sends'));

class _FavoriteValueDialog extends StatefulWidget {
  const _FavoriteValueDialog(
      {required this.title,
      required this.label,
      required this.onSave,
      this.hint});
  final String title;
  final String label;
  final String? hint;
  final Future<void> Function(String) onSave;
  @override
  State<_FavoriteValueDialog> createState() => _FavoriteValueDialogState();
}

class _FavoriteValueDialogState extends State<_FavoriteValueDialog> {
  late final TextEditingController _value;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _value = TextEditingController();
  }

  Future<void> _save() async {
    if (_saving || _value.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_value.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FavoriteApiException
            ? error.message
            : settingsText(context,
                zh: '保存失败，请重试', en: 'Could not save. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
          title: Text(widget.title),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                key: const ValueKey('favorite-value-input'),
                controller: _value,
                enabled: !_saving,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                keyboardType: widget.hint == 'https://'
                    ? TextInputType.url
                    : TextInputType.text,
                decoration: InputDecoration(
                    labelText: widget.label, hintText: widget.hint)),
            if (_saving) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(
                  liveRegion: true,
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
          ])),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(settingsText(context, zh: '取消', en: 'Cancel'))),
            FilledButton(
                key: const ValueKey('favorite-value-save'),
                onPressed: _saving || _value.text.trim().isEmpty ? null : _save,
                child: Text(settingsText(context, zh: '保存', en: 'Save'))),
          ]));
}

class FavoriteItemTile extends StatelessWidget {
  const FavoriteItemTile(
      {super.key,
      required this.item,
      this.repository,
      this.onTap,
      this.onLongPress,
      this.trailing,
      this.selectionMode = false,
      this.selected = false});
  final FavoriteItem item;
  final FavoriteRepository? repository;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final title = item.title.trim().isNotEmpty
        ? item.title
        : item.summary.trim().isNotEmpty
            ? item.summary
            : favoriteKindLabel(context, item.kind);
    final status = favoriteStatusLabel(context, item);
    return Material(
      color: selected
          ? AppTokens.accent.withValues(alpha: 0.12)
          : AppTokens.surface(dark: dark),
      borderRadius: BorderRadius.circular(AppTokens.rLg),
      clipBehavior: Clip.antiAlias,
      child: Row(children: [
        Expanded(
            child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.s5),
            child: LayoutBuilder(
                builder: (context, constraints) => Row(children: [
                      if (selectionMode) ...[
                        Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: selected
                                ? AppTokens.accent
                                : settingsSecondaryTextColor(context)),
                        const SizedBox(width: AppTokens.s4),
                      ],
                      Container(
                        width: item.kind == FavoriteKind.audio
                            ? ((constraints.maxWidth -
                                        (selectionMode
                                            ? AppTokens.s7 + AppTokens.s4
                                            : 0)) /
                                    2)
                                .clamp(FavoriteMediaTokens.audioHeight,
                                    FavoriteMediaTokens.audioWidth)
                            : AppTokens.s8 + AppTokens.s5,
                        height: item.kind == FavoriteKind.audio
                            ? FavoriteMediaTokens.audioHeight
                            : AppTokens.s8 + AppTokens.s5,
                        decoration: BoxDecoration(
                            color: AppTokens.surfaceAlt(dark: dark),
                            borderRadius: BorderRadius.circular(AppTokens.rMd)),
                        clipBehavior: Clip.antiAlias,
                        child: repository != null &&
                                {
                                  FavoriteKind.image,
                                  FavoriteKind.video,
                                  FavoriteKind.audio
                                }.contains(item.kind)
                            ? FavoriteItemThumbnail(
                                key: ValueKey('${item.id}:${item.version}'),
                                repository: repository!,
                                item: item)
                            : Icon(favoriteKindIcon(item.kind),
                                color: AppTokens.accent),
                      ),
                      const SizedBox(width: AppTokens.s4),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: AppTokens.textPrimary(dark: dark),
                                    fontSize: AppTokens.listTitleFontSize)),
                            const SizedBox(height: AppTokens.s3),
                            Text(
                                status.isEmpty
                                    ? favoriteKindLabel(context, item.kind)
                                    : status,
                                style: TextStyle(
                                    color: settingsSecondaryTextColor(context),
                                    fontSize: AppTokens.captionFontSize)),
                          ])),
                      if (trailing == null && !selectionMode)
                        Icon(Icons.chevron_right_rounded,
                            color: settingsSecondaryTextColor(context)),
                    ])),
          ),
        )),
        if (trailing != null)
          Padding(
              padding: const EdgeInsets.only(right: AppTokens.s3),
              child: trailing!),
      ]),
    );
  }
}

IconData favoriteKindIcon(FavoriteKind kind) => switch (kind) {
      FavoriteKind.text || FavoriteKind.note => Icons.description_outlined,
      FavoriteKind.image => Icons.image_outlined,
      FavoriteKind.video => Icons.videocam_outlined,
      FavoriteKind.audio => Icons.mic_none_outlined,
      FavoriteKind.file => Icons.insert_drive_file_outlined,
      FavoriteKind.link => Icons.link_outlined,
      FavoriteKind.location => Icons.location_on_outlined,
      FavoriteKind.contact => Icons.person_outline,
      FavoriteKind.messageBundle => Icons.forum_outlined,
      FavoriteKind.unknown => Icons.help_outline,
    };

String favoriteKindLabel(BuildContext context, FavoriteKind kind) {
  final labels = switch (kind) {
    FavoriteKind.text => ('文字', 'Text'),
    FavoriteKind.note => ('笔记', 'Notes'),
    FavoriteKind.image => ('图片', 'Images'),
    FavoriteKind.video => ('视频', 'Videos'),
    FavoriteKind.audio => ('语音', 'Audio'),
    FavoriteKind.file => ('文件', 'Files'),
    FavoriteKind.link => ('链接', 'Links'),
    FavoriteKind.location => ('定位', 'Locations'),
    FavoriteKind.contact => ('名片', 'Contacts'),
    FavoriteKind.messageBundle => ('聊天记录', 'Chat history'),
    FavoriteKind.unknown => ('暂不支持的内容', 'Unsupported content'),
  };
  return settingsText(context, zh: labels.$1, en: labels.$2);
}

String favoriteStatusLabel(BuildContext context, FavoriteItem item) {
  if (!item.isSupported) {
    return settingsText(context,
        zh: '此版本暂不支持查看或发送',
        en: 'This version cannot view or send this content');
  }
  return switch (item.status) {
    FavoriteStatus.ready => '',
    FavoriteStatus.pendingArchive => settingsText(context,
        zh: '正在保存，完成后可发送', en: 'Saving; sending is available when ready'),
    FavoriteStatus.failed => settingsText(context,
        zh: '保存失败，可在详情中重试', en: 'Could not save. Retry from details'),
    FavoriteStatus.deleted => settingsText(context, zh: '已删除', en: 'Deleted'),
    FavoriteStatus.unknown =>
      settingsText(context, zh: '内容暂不可用', en: 'Content unavailable'),
  };
}
