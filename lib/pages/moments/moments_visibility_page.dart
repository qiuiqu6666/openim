import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../services/moments_repository.dart';
import 'moments_draft_store.dart';
import 'moments_widgets.dart';
import 'presentation/moments_secondary_layout.dart';

/// Select the post's audience locally; the backend remains the authority.
class MomentsVisibilityPage extends StatefulWidget {
  const MomentsVisibilityPage(
      {super.key,
      required this.repository,
      this.initialSelection = const MomentsVisibilitySelection()});
  final MomentsRepository repository;
  final MomentsVisibilitySelection initialSelection;
  @override
  State<MomentsVisibilityPage> createState() => _MomentsVisibilityPageState();
}

class _MomentsVisibilityPageState extends State<MomentsVisibilityPage> {
  late String _mode;
  late final Set<String> _selected;
  List<MomentUser> _friends = [];
  bool _loading = false;
  bool _friendsLoaded = false;
  Object? _error;
  String _query = '';
  final _search = TextEditingController();
  late final String _scope;
  bool get _needsFriends => _mode == 'PARTIAL' || _mode == 'EXCLUDE';

  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
    _mode = widget.initialSelection.mode;
    _selected = widget.initialSelection.audienceUserIds.toSet();
    widget.repository.addListener(_repositoryChanged);
    if (_needsFriends) _loadFriends();
  }

  void _repositoryChanged() {
    if (!mounted || widget.repository.isSessionCurrent(_scope)) return;
    setState(() {
      _friends = [];
      _selected.clear();
      _query = '';
      _search.clear();
      _error = const MomentsException('Session changed', authRequired: true);
    });
  }

  @override
  void dispose() {
    widget.repository.removeListener(_repositoryChanged);
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final friends = await widget.repository.loadFriends();
      if (!mounted || !widget.repository.isSessionCurrent(_scope)) return;
      setState(() {
        _friends = friends;
        _friendsLoaded = true;
        // Removed friends cannot stay invisibly selected in an old draft.
        _selected
            .removeWhere((id) => !friends.any((user) => user.userId == id));
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectMode(String mode) {
    setState(() => _mode = mode);
    if (_needsFriends && !_friendsLoaded) _loadFriends();
  }

  void _done() {
    if (!widget.repository.isSessionCurrent(_scope)) return;
    if (_needsFriends &&
        (!_friendsLoaded || _selected.isEmpty || _error != null)) {
      return;
    }
    Navigator.of(context).pop(MomentsVisibilitySelection(
        mode: _mode,
        audienceUserIds: _needsFriends ? _selected.toList() : const []));
  }

  String _title(String mode) => switch (mode) {
        'SELF' => momentsText(context, zh: '仅自己', en: 'Only me'),
        'PARTIAL' => momentsText(context, zh: '部分好友可见', en: 'Selected friends'),
        'EXCLUDE' => momentsText(context, zh: '不给谁看', en: 'Exclude friends'),
        _ => momentsText(context, zh: '所有好友', en: 'All friends'),
      };
  String _description(String mode) => switch (mode) {
        'SELF' => momentsText(context,
            zh: '只有你可以查看这条动态', en: 'Only you can see this post'),
        'PARTIAL' => momentsText(context,
            zh: '选择可以查看的好友', en: 'Choose friends who can see this post'),
        'EXCLUDE' => momentsText(context,
            zh: '所选好友无法查看这条动态', en: 'Hide this post from selected friends'),
        _ => momentsText(context,
            zh: '你的当前好友可以查看', en: 'Your current friends can see this post'),
      };
  IconData _icon(String mode) => switch (mode) {
        'SELF' => Icons.lock_outline_rounded,
        'PARTIAL' => Icons.group_outlined,
        'EXCLUDE' => Icons.person_off_outlined,
        _ => Icons.people_outline_rounded,
      };
  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    final current = widget.repository.isSessionCurrent(_scope);
    final canConfirm = current &&
        (!_needsFriends ||
            (!_loading &&
                _error == null &&
                _friendsLoaded &&
                _selected.isNotEmpty));
    final friends = _friends
        .where((user) =>
            user.displayName.toLowerCase().contains(_query.toLowerCase()) ||
            user.userId.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Scaffold(
      backgroundColor: MomentsTheme.card(dark),
      appBar: TitleBar(
        left: IconButton(
            tooltip: momentsText(context, zh: '返回', en: 'Back'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded)),
        center: Expanded(
            child: Text(
                momentsText(context, zh: '谁可以看', en: 'Who can see this'),
                style: TextStyle(
                    color: MomentsTheme.text(dark),
                    fontSize: MomentsSecondaryLayout.titleSize,
                    fontWeight: FontWeight.w600))),
      ),
      bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.s5),
            child: FilledButton(
                key: const ValueKey('moments_visibility_done'),
                onPressed: canConfirm ? _done : null,
                child: Text(momentsText(context, zh: '完成', en: 'Done'))),
          )),
      body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: MomentsLayout.pageMaxWidth),
              child: CustomScrollView(slivers: [
                SliverPadding(
                    padding: const EdgeInsets.all(AppTokens.s5),
                    sliver: SliverToBoxAdapter(
                      child: Material(
                        color: MomentsTheme.card(dark),
                        borderRadius: BorderRadius.zero,
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          for (final mode in const [
                            'FRIENDS',
                            'SELF',
                            'PARTIAL',
                            'EXCLUDE'
                          ])
                            Semantics(
                                selected: _mode == mode,
                                child: ListTile(
                                  key: ValueKey('moments_visibility_$mode'),
                                  leading: Icon(_icon(mode),
                                      color: MomentsTheme.secondary(dark)),
                                  title: Text(_title(mode)),
                                  subtitle: Text(_description(mode)),
                                  trailing: Icon(
                                      _mode == mode
                                          ? Icons.check_circle_rounded
                                          : Icons
                                              .radio_button_unchecked_rounded,
                                      color: _mode == mode
                                          ? AppTokens.accent
                                          : AppTokens.textSecondary(
                                              dark: dark)),
                                  onTap:
                                      current ? () => _selectMode(mode) : null,
                                )),
                        ]),
                      ),
                    )),
                if (!current)
                  SliverToBoxAdapter(
                      child: MomentsStatePanel(
                    icon: Icons.lock_outline_rounded,
                    title: momentsText(context,
                        zh: '登录状态已改变', en: 'Session changed'),
                    message: momentsText(context,
                        zh: '请重新进入朋友圈', en: 'Open Moments again to continue'),
                  ))
                else if (_needsFriends) ...[
                  SliverPadding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppTokens.s5),
                    sliver: SliverToBoxAdapter(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              momentsText(context,
                                  zh: '已选择 ${_selected.length} 位好友',
                                  en: '${_selected.length} friends selected'),
                              style: TextStyle(
                                  color: MomentsTheme.secondary(dark))),
                          const SizedBox(height: AppTokens.s3),
                          TextField(
                              key: const ValueKey('moments_friend_search'),
                              controller: _search,
                              decoration: InputDecoration(
                                  labelText: momentsText(context,
                                      zh: '搜索好友', en: 'Search friends'),
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  filled: true,
                                  isDense: true,
                                  fillColor: MomentsTheme.panel(dark),
                                  border: OutlineInputBorder(
                                      borderSide: BorderSide.none,
                                      borderRadius: BorderRadius.circular(
                                          MomentsSecondaryLayout.imageRadius))),
                              onChanged: (value) =>
                                  setState(() => _query = value.trim())),
                          const SizedBox(height: AppTokens.s4),
                        ])),
                  ),
                  if (_loading)
                    const SliverToBoxAdapter(
                        child: Padding(
                            padding: EdgeInsets.all(AppTokens.s7),
                            child: Center(child: CircularProgressIndicator())))
                  else if (_error != null)
                    SliverToBoxAdapter(
                        child: MomentsStatePanel(
                            icon: Icons.wifi_off_rounded,
                            title: momentsText(context,
                                zh: '好友列表加载失败', en: 'Could not load friends'),
                            message: momentsErrorText(context, _error!),
                            onAction: _loadFriends,
                            actionLabel:
                                momentsText(context, zh: '重试', en: 'Retry')))
                  else if (friends.isEmpty)
                    SliverToBoxAdapter(
                        child: MomentsStatePanel(
                            icon: Icons.people_outline_rounded,
                            title: momentsText(context,
                                zh: _query.isEmpty ? '暂无好友' : '未找到好友',
                                en: _query.isEmpty
                                    ? 'No friends yet'
                                    : 'No matching friends'),
                            message: momentsText(context,
                                zh: '添加好友后可设置选人范围',
                                en: 'Add friends to use a selected audience')))
                  else
                    SliverList.builder(
                        itemCount: friends.length,
                        itemBuilder: (_, index) {
                          final user = friends[index];
                          return CheckboxListTile(
                              key: ValueKey('moments_friend_${user.userId}'),
                              value: _selected.contains(user.userId),
                              activeColor: AppTokens.accent,
                              secondary: AvatarView(
                                  url: user.avatarUrl,
                                  text: user.displayName,
                                  width: MomentsLayout.avatarSize,
                                  height: MomentsLayout.avatarSize),
                              title: Text(user.displayName),
                              onChanged: (_) => setState(() {
                                    if (!_selected.add(user.userId)) {
                                      _selected.remove(user.userId);
                                    }
                                  }));
                        }),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: AppTokens.s7)),
              ]),
            ),
          )),
    );
  }
}
