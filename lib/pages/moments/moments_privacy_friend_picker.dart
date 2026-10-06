import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/moments_repository.dart';
import 'moments_widgets.dart';
import 'presentation/moments_friend_picker_list.dart';
import 'presentation/moments_secondary_layout.dart';

/// Selects additional privacy-list entries from a fresh repository read.
/// Selection never changes a post's visibility or writes settings by itself.
class MomentsPrivacyFriendPicker extends StatefulWidget {
  const MomentsPrivacyFriendPicker({
    super.key,
    required this.repository,
    required this.title,
    this.excludedUserIds = const [],
    this.initialSelectedIds = const [],
  });

  final MomentsRepository repository;
  final String title;
  final List<String> excludedUserIds;
  final List<String> initialSelectedIds;

  @override
  State<MomentsPrivacyFriendPicker> createState() =>
      _MomentsPrivacyFriendPickerState();
}

class _MomentsPrivacyFriendPickerState
    extends State<MomentsPrivacyFriendPicker> {
  List<MomentUser> _friends = const [];
  final Set<String> _selected = {};
  final _search = TextEditingController();
  bool _loading = true;
  bool _allAlreadyAdded = false;
  Object? _error;
  String _query = '';
  int _generation = 0;
  late String _scope;

  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
    _selected.addAll(widget.initialSelectedIds);
    widget.repository.addListener(_repositoryChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant MomentsPrivacyFriendPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.removeListener(_repositoryChanged);
      widget.repository.addListener(_repositoryChanged);
      _scope = widget.repository.sessionScope;
      _friends = const [];
      _selected.clear();
      _query = '';
      _search.clear();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    ++_generation;
    widget.repository.removeListener(_repositoryChanged);
    _search.dispose();
    super.dispose();
  }

  void _repositoryChanged() {
    if (!mounted || widget.repository.isSessionCurrent(_scope)) return;
    ++_generation;
    setState(() {
      _friends = const [];
      _selected.clear();
      _query = '';
      _search.clear();
      _loading = false;
      _error = const MomentsException('会话已改变', authRequired: true);
    });
  }

  Future<void> _load() async {
    if (!widget.repository.isSessionCurrent(_scope)) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final friends = await widget.repository.loadFriends(force: true);
      if (!mounted ||
          generation != _generation ||
          !widget.repository.isSessionCurrent(_scope)) {
        return;
      }
      final excluded = widget.excludedUserIds.toSet();
      final available = friends
          .where((friend) => !excluded.contains(friend.userId))
          .toList(growable: false);
      setState(() {
        _friends = available;
        _allAlreadyAdded = friends.isNotEmpty && available.isEmpty;
        _selected.removeWhere(
            (id) => !available.any((friend) => friend.userId == id));
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _toggle(MomentUser friend) {
    if (_loading ||
        _error != null ||
        !widget.repository.isSessionCurrent(_scope)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (!_selected.add(friend.userId)) _selected.remove(friend.userId);
    });
  }

  void _done() {
    if (_loading ||
        _error != null ||
        _selected.isEmpty ||
        !widget.repository.isSessionCurrent(_scope)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop<List<MomentUser>>(_friends
        .where((friend) => _selected.contains(friend.userId))
        .toList(growable: false));
  }

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    final current = widget.repository.isSessionCurrent(_scope);
    final canConfirm =
        current && !_loading && _error == null && _selected.isNotEmpty;
    final query = _query.trim().toLowerCase();
    final items = _friends
        .where((friend) =>
            friend.displayName.toLowerCase().contains(query) ||
            friend.userId.toLowerCase().contains(query))
        .toList(growable: false);
    Widget content;
    if (_loading) {
      content = const Center(child: CupertinoActivityIndicator());
    } else if (_error != null || !current) {
      content = SingleChildScrollView(
          child: MomentsStatePanel(
        icon: Icons.cloud_off_rounded,
        title: momentsText(context, zh: '好友加载失败', en: 'Could not load friends'),
        message: momentsErrorText(context,
            _error ?? const MomentsException('会话已改变', authRequired: true)),
        actionLabel: momentsText(context, zh: '重试', en: 'Retry'),
        onAction: current ? () => unawaited(_load()) : null,
      ));
    } else if (items.isEmpty) {
      content = SingleChildScrollView(
          child: MomentsStatePanel(
        icon: Icons.people_outline_rounded,
        title: momentsText(context,
            zh: query.isNotEmpty
                ? '没有找到朋友'
                : _allAlreadyAdded
                    ? '所有朋友都已添加'
                    : '还没有朋友',
            en: query.isNotEmpty
                ? 'No matching friends'
                : _allAlreadyAdded
                    ? 'All friends are already added'
                    : 'No friends yet'),
        message: momentsText(context,
            zh: query.isNotEmpty
                ? '试试其他昵称或用户 ID。'
                : _allAlreadyAdded
                    ? '可以在名单中移除已有朋友。'
                    : '添加朋友后，可以在这里选择。',
            en: query.isNotEmpty
                ? 'Try another name or user ID.'
                : _allAlreadyAdded
                    ? 'You can remove friends from the privacy list.'
                    : 'Add friends to choose them here.'),
      ));
    } else {
      content = MomentsFriendPickerList(
        friends: items,
        selected: _selected,
        onToggle: _toggle,
        showIndex: query.isEmpty,
      );
    }
    return Scaffold(
      backgroundColor: MomentsTheme.card(dark),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: MomentsTheme.card(dark),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
            tooltip: momentsText(context, zh: '关闭', en: 'Close'),
            icon: const Icon(Icons.close_rounded),
            color: MomentsTheme.nav(dark),
            onPressed: () => Navigator.of(context).maybePop()),
        title: Text(widget.title,
            style: TextStyle(
                color: MomentsTheme.text(dark),
                fontSize: MomentsSecondaryLayout.titleSize,
                fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            key: const ValueKey('moments_privacy_picker_done'),
            onPressed: canConfirm ? _done : null,
            style: TextButton.styleFrom(
                foregroundColor: MomentsTheme.name(dark),
                disabledForegroundColor: MomentsTheme.secondary(dark)),
            child: Text(momentsText(context, zh: '完成', en: 'Done'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          )
        ],
      ),
      body: SafeArea(
          top: false,
          child: Column(children: [
            Padding(
              padding: MomentsSecondaryLayout.searchInset,
              child: Semantics(
                label: momentsText(context,
                    zh: '已选择 ${_selected.length} 位朋友',
                    en: '${_selected.length} friends selected'),
                child: TextField(
                  key: const ValueKey('moments_privacy_friend_search'),
                  controller: _search,
                  enabled: current && !_loading && _error == null,
                  decoration: InputDecoration(
                    hintText: momentsText(context, zh: '搜索', en: 'Search'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey('moments_privacy_search_clear'),
                            tooltip: momentsText(context,
                                zh: '清除搜索', en: 'Clear search'),
                            onPressed: current && !_loading && _error == null
                                ? () {
                                    _search.clear();
                                    setState(() => _query = '');
                                  }
                                : null,
                            icon: const Icon(Icons.close_rounded)),
                    filled: true,
                    fillColor: MomentsTheme.panel(dark),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(
                            MomentsSecondaryLayout.imageRadius)),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            ),
            Expanded(child: content),
          ])),
    );
  }
}
