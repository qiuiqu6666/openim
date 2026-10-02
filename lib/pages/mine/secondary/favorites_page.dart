import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../settings/settings_navigation.dart';
import '../settings/widgets/settings_widgets.dart';
import 'favorite_note_edit_page.dart';
import 'favorites_draft_store.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, required this.store});

  final FavoritesDraftStore store;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
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
    if (day == yesterday) return settingsText(context, zh: '昨天', en: 'Yesterday');
    if (now.difference(day).inDays < 7) {
      const zhWeekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
      const enWeekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return _isZh ? zhWeekdays[local.weekday - 1] : enWeekdays[local.weekday - 1];
    }
    return _isZh
        ? '${local.year}年${local.month}月${local.day}日'
        : '${local.month}/${local.day}/${local.year}';
  }

  Map<String, List<FavoriteDraftItem>> _groupByDate(List<FavoriteDraftItem> items) {
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
      final count = type == null ? items.length : items.where((e) => e.type == type).length;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(() => _filter = type),
          side: BorderSide.none,
          shape: const StadiumBorder(),
          selectedColor: dark ? const Color(0xFF20344D) : const Color(0xFFEAF2FF),
          backgroundColor: fill,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: selected ? AppTokens.accent : secondary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(color: selected ? AppTokens.accent : secondary),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTokens.accent
                      : (dark ? const Color(0xFF3A404B) : const Color(0xFFE6EBF2)),
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
                hintText: settingsText(context, zh: '搜索收藏内容', en: 'Search favorites'),
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
                        chip(null, settingsText(context, zh: '全部', en: 'All'), null),
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
              direction: _editing ? DismissDirection.none : DismissDirection.endToStart,
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
                  ? settingsText(context, zh: '没有匹配的收藏', en: 'No matching favorites')
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
            appBar: AppBar(
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: true,
              backgroundColor: AppTokens.surface(dark: dark),
              surfaceTintColor: Colors.transparent,
              leading: Navigator.of(context).canPop()
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: AppTokens.accent,
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
              title: Text(
                settingsText(context, zh: '收藏', en: 'Favorites'),
                style: TextStyle(
                  color: AppTokens.textPrimary(dark: dark),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                if (items.isNotEmpty)
                  TextButton(
                    key: const ValueKey('favorites-edit'),
                    onPressed: _toggleEditing,
                    child: Text(
                      _editing
                          ? settingsText(context, zh: '完成', en: 'Done')
                          : settingsText(context, zh: '编辑', en: 'Edit'),
                      style: const TextStyle(color: AppTokens.accent, fontSize: 16),
                    ),
                  ),
              ],
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
                                title: settingsText(context, zh: '暂无收藏', en: 'No favorites yet'),
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
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  child: Text(settingsText(context, zh: '添加收藏', en: 'Add Favorite')),
                                ),
                              ),
                            ),
                          ],
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            await Future<void>.delayed(const Duration(milliseconds: 120));
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
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
                          onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE64340),
                            disabledBackgroundColor: AppTokens.border(dark: dark),
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
        child: const Icon(Icons.title_rounded, size: 27, color: Color(0xFF568EFF)),
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
                  decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
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
      FavoriteDraftType.note => settingsText(context, zh: '文字收藏', en: 'Text favorite'),
      FavoriteDraftType.image => settingsText(context, zh: '图片收藏', en: 'Image favorite'),
      FavoriteDraftType.video => settingsText(context, zh: '视频收藏', en: 'Video favorite'),
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
                            item.type == FavoriteDraftType.note && item.text.trim().isNotEmpty
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
                          Icon(Icons.chevron_right_rounded, size: 22, color: secondary),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(typeText, style: TextStyle(color: secondary, fontSize: 12.5)),
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
