import 'package:azlistview/azlistview.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../contacts/directory/contact_directory_snapshot.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_draft_store.dart';
import '../widgets/settings_widgets.dart';

class MomentsFriendPickerPage extends StatefulWidget {
  const MomentsFriendPickerPage({
    super.key,
    required this.title,
    this.initialSelectedIds = const [],
  });

  final String title;
  final List<String> initialSelectedIds;

  @override
  State<MomentsFriendPickerPage> createState() =>
      _MomentsFriendPickerPageState();
}

class _MomentsFriendPickerPageState extends State<MomentsFriendPickerPage> {
  bool _loading = true;
  String _keyword = '';
  List<ISUserInfo> _friends = const [];
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(widget.initialSelectedIds.where((e) => e.isNotEmpty));
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() => _loading = true);
    try {
      final converted = await loadContactDirectorySnapshot();
      if (!mounted) return;
      setState(() {
        _friends = converted;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _friends = const [];
        _loading = false;
      });
    }
  }

  List<ISUserInfo> get _filtered {
    final keyword = _keyword.trim().toLowerCase();
    if (keyword.isEmpty) return _friends;
    return _friends.where((item) {
      final name = item.showName.toLowerCase();
      final id = (item.userID ?? '').toLowerCase();
      return name.contains(keyword) || id.contains(keyword);
    }).toList(growable: false);
  }

  void _toggle(ISUserInfo item) {
    final id = item.userID?.trim() ?? '';
    if (id.isEmpty) return;
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _confirm() {
    final picked = <SettingsContactDraft>[];
    for (final item in _friends) {
      final id = item.userID?.trim() ?? '';
      if (id.isEmpty || !_selectedIds.contains(id)) continue;
      picked.add(
        SettingsContactDraft(
          userId: id,
          displayName: item.showName,
          avatarUrl: item.faceURL?.trim() ?? '',
        ),
      );
    }
    Navigator.of(context).pop(picked);
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final items = _filtered;
    final showIndexBar = _keyword.trim().isEmpty;
    final line = AppTokens.border(dark: dark);
    const pickerNameColor = AppTokens.ink600;

    return Scaffold(
      backgroundColor: AppTokens.surface(dark: dark),
      appBar: GlassAppBar(
        toolbarHeight: kToolbarHeight,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppTokens.surface(dark: dark),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          color: pickerNameColor,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            color: AppTokens.textPrimary(dark: dark),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _selectedIds.isEmpty ? null : _confirm,
            child: Text(
              settingsText(context, zh: '完成', en: 'Done'),
              style: TextStyle(
                color: _selectedIds.isEmpty
                    ? AppTokens.textSecondary(dark: dark)
                    : pickerNameColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: settingsText(context, zh: '搜索', en: 'Search'),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: settingsSurfaceAlt(dark),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _keyword = value),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator())
                : items.isEmpty
                    ? Center(
                        child: Text(
                          _keyword.trim().isEmpty
                              ? settingsText(context,
                                  zh: '暂无好友', en: 'No friends')
                              : settingsText(context,
                                  zh: '未找到相关好友', en: 'No matching friends'),
                          style: TextStyle(
                            color: AppTokens.textSecondary(dark: dark),
                          ),
                        ),
                      )
                    : AzListView(
                        data: items,
                        itemCount: items.length,
                        indexBarData: showIndexBar
                            ? SuspensionUtil.getTagIndexList(items)
                            : const [],
                        indexBarOptions: IndexBarOptions(
                          needRebuild: true,
                          selectTextStyle: const TextStyle(color: Colors.white),
                          indexHintWidth: 64,
                          indexHintHeight: 64,
                          indexHintTextStyle: TextStyle(
                            color: AppTokens.textPrimary(dark: dark),
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        susItemHeight: 32,
                        susItemBuilder: (_, index) {
                          final item = items[index];
                          return Container(
                            height: 32,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            color: settingsSurfaceAlt(dark),
                            child: Text(
                              item.getSuspensionTag(),
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTokens.textSecondary(dark: dark),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                        itemBuilder: (_, index) {
                          final item = items[index];
                          final id = item.userID?.trim() ?? '';
                          final selected = _selectedIds.contains(id);
                          final next = index + 1;
                          final showDivider = next < items.length &&
                              !items[next].isShowSuspension;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _toggle(item),
                              child: Container(
                                decoration: showDivider
                                    ? BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: line,
                                            width: 0.7,
                                          ),
                                        ),
                                      )
                                    : null,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 10, 16, 10),
                                child: Row(
                                  children: [
                                    AvatarView(
                                      url: item.faceURL,
                                      text: item.showName,
                                      width: 44,
                                      height: 44,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        item.showName,
                                        style: TextStyle(
                                          color:
                                              AppTokens.textPrimary(dark: dark),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      selected
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      color: selected
                                          ? pickerNameColor
                                          : AppTokens.textSecondary(dark: dark),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
