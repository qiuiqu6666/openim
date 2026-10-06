import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../services/moments_repository.dart';
import '../mine/settings/widgets/settings_widgets.dart';
import 'moments_privacy_friend_picker.dart';
import 'moments_widgets.dart';
import 'presentation/moments_secondary_layout.dart';

enum MomentsPrivacyKind { blockedViewer, hiddenAuthor }

/// Shows device-confirmed choices and writes individual relationships.
class MomentsPrivacyListPage extends StatefulWidget {
  const MomentsPrivacyListPage(
      {super.key, required this.repository, required this.kind});

  final MomentsRepository repository;
  final MomentsPrivacyKind kind;

  @override
  State<MomentsPrivacyListPage> createState() => _MomentsPrivacyListPageState();
}

class _MomentsPrivacyListPageState extends State<MomentsPrivacyListPage> {
  final Map<String, MomentUser> _friends = {};
  final List<String> _pendingIds = [];
  bool _pendingEnabled = true;
  bool _loading = true;
  bool _saving = false;
  bool _pickingFriends = false;
  Object? _error;
  Object? _persistenceRetryError;
  int _requestGeneration = 0;
  late String _scope;

  bool get _listLoaded =>
      widget.repository.isSessionCurrent(_scope) &&
      widget.repository.privacySelectionsLoaded;

  List<String> get _ids => !_listLoaded
      ? const []
      : widget.kind == MomentsPrivacyKind.blockedViewer
          ? widget.repository.privacySelections.blockedViewerIds
          : widget.repository.privacySelections.hiddenAuthorIds;

  bool _current(int request, String scope) =>
      mounted &&
      request == _requestGeneration &&
      widget.repository.isSessionCurrent(scope);

  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
    widget.repository.addListener(_repositoryChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant MomentsPrivacyListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.kind != widget.kind) {
      oldWidget.repository.removeListener(_repositoryChanged);
      widget.repository.addListener(_repositoryChanged);
      _scope = widget.repository.sessionScope;
      _friends.clear();
      _pendingIds.clear();
      _saving = false;
      _persistenceRetryError = null;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    ++_requestGeneration;
    widget.repository.removeListener(_repositoryChanged);
    super.dispose();
  }

  void _repositoryChanged() {
    if (!mounted) return;
    if (!widget.repository.isSessionCurrent(_scope)) {
      ++_requestGeneration;
      // Keep the original scope so an old page cannot edit the next session.
      setState(() {
        _friends.clear();
        _pendingIds.clear();
        _loading = false;
        _saving = false;
        _persistenceRetryError = null;
        _error = const MomentsException('会话已改变，请重新打开朋友圈', authRequired: true);
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _load({bool force = false}) async {
    if (!widget.repository.isSessionCurrent(_scope)) return;
    final request = ++_requestGeneration;
    final scope = _scope;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.repository.loadPrivacySelections(force: force);
      if (!_current(request, scope)) return;
      final friends = await widget.repository.loadFriends();
      if (!_current(request, scope)) return;
      setState(() {
        _friends
          ..clear()
          ..addEntries(
              friends.map((friend) => MapEntry(friend.userId, friend)));
      });
    } catch (error) {
      if (_current(request, scope)) setState(() => _error = error);
    } finally {
      if (_current(request, scope)) setState(() => _loading = false);
    }
  }

  Future<void> _setEntry(String id, bool enabled) async {
    if (widget.kind == MomentsPrivacyKind.blockedViewer) {
      await widget.repository.setBlockedViewer(id, enabled);
    } else {
      await widget.repository.setHiddenAuthor(id, enabled);
    }
  }

  Future<void> _saveEntries(List<String> ids, bool enabled) async {
    if (_saving || _loading || !_listLoaded) return;
    setState(() {
      _pendingIds
        ..clear()
        ..addAll(ids.toSet());
      _pendingEnabled = enabled;
      _persistenceRetryError = null;
    });
    await _continueSave();
  }

  Future<void> _continueSave() async {
    if (_saving || _loading || !_listLoaded || _pendingIds.isEmpty) return;
    final request = _requestGeneration;
    final scope = _scope;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      while (_pendingIds.isNotEmpty) {
        if (!_current(request, scope)) return;
        final id = _pendingIds.first;
        await _setEntry(id, _pendingEnabled);
        if (!_current(request, scope)) return;
        // Repository choices update only after a successful command. A local
        // persistence failure does not replay that successful server command.
        setState(() => _pendingIds.removeAt(0));
      }
    } catch (error) {
      if (_current(request, scope)) setState(() => _error = error);
    } finally {
      if (_current(request, scope)) setState(() => _saving = false);
    }
  }

  Future<void> _pickFriends({required bool enabled}) async {
    if (_saving || _loading || !_listLoaded || _pickingFriends) return;
    _pickingFriends = true;
    final request = _requestGeneration;
    final scope = _scope;
    final picked = await Navigator.of(context).push<List<MomentUser>>(
      MaterialPageRoute(
          builder: (_) => MomentsPrivacyFriendPicker(
                repository: widget.repository,
                title: momentsText(context,
                    zh: enabled ? '添加朋友' : '选择朋友移除',
                    en: enabled ? 'Add friends' : 'Choose friends to remove'),
                // All friends remain selectable: PUT is idempotent, and DELETE
                // can cancel a choice made on another device.
              )),
    );
    _pickingFriends = false;
    if (!_current(request, scope) || picked == null || picked.isEmpty) return;
    setState(() => _friends
        .addEntries(picked.map((friend) => MapEntry(friend.userId, friend))));
    await _saveEntries(picked.map((friend) => friend.userId).toList(), enabled);
  }

  Future<void> _retryPersistence() async {
    if (_saving || _loading || !_listLoaded) return;
    final request = _requestGeneration;
    final scope = _scope;
    setState(() {
      _saving = true;
      _persistenceRetryError = null;
    });
    try {
      await widget.repository.retryPrivacyPersistence();
    } catch (error) {
      if (_current(request, scope)) {
        setState(() => _persistenceRetryError = error);
      }
    } finally {
      if (_current(request, scope)) setState(() => _saving = false);
    }
  }

  Widget _addButton(bool canEdit, {bool compact = false}) {
    final dark = momentsDark(context);
    return Center(
        child: Material(
      color: MomentsTheme.panel(dark),
      borderRadius:
          BorderRadius.circular(MomentsSecondaryLayout.addButtonRadius),
      child: InkWell(
        key: const ValueKey('moments_privacy_add'),
        onTap: canEdit ? () => unawaited(_pickFriends(enabled: true)) : null,
        borderRadius:
            BorderRadius.circular(MomentsSecondaryLayout.addButtonRadius),
        child: Container(
          width: compact ? null : MomentsSecondaryLayout.addButtonWidth,
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
              : MomentsSecondaryLayout.addButtonInset,
          decoration: BoxDecoration(
              border: Border.all(color: MomentsTheme.border(dark)),
              borderRadius: BorderRadius.circular(
                  MomentsSecondaryLayout.addButtonRadius)),
          child: Text(momentsText(context, zh: '添加', en: 'Add friends'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: canEdit
                      ? MomentsTheme.text(dark)
                      : MomentsTheme.secondary(dark),
                  fontSize: MomentsSecondaryLayout.nameSize,
                  fontWeight: FontWeight.w500)),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final blocked = widget.kind == MomentsPrivacyKind.blockedViewer;
    final ids = _ids;
    final error = _error;
    final unavailable = error is MomentsException && error.unavailable;
    final current = widget.repository.isSessionCurrent(_scope);
    final persistenceError = current && _listLoaded
        ? _persistenceRetryError ?? widget.repository.privacyPersistenceError
        : null;
    final canEdit = !_saving && !_loading && _listLoaded;
    return SettingsScaffold(
      title: momentsText(context,
          zh: blocked
              ? '不让他(她)看我的朋友圈 (${ids.length})'
              : '不看他(她)的朋友圈 (${ids.length})',
          en: blocked ? 'Hide my posts from' : 'Hide their posts'),
      children: [
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(AppTokens.s8),
              child: Center(child: CupertinoActivityIndicator())),
        if (error != null)
          MomentsStatePanel(
            icon: unavailable
                ? Icons.info_outline_rounded
                : Icons.cloud_off_rounded,
            title: momentsText(context,
                zh: unavailable ? '朋友圈尚未开放' : '操作未能完成',
                en: unavailable
                    ? 'Moments is not available yet'
                    : 'Could not complete this action'),
            message: momentsErrorText(context, error),
            actionLabel: momentsText(context,
                zh: _pendingIds.isNotEmpty ? '重试未完成选择' : '重新加载',
                en: _pendingIds.isNotEmpty
                    ? 'Retry remaining choices'
                    : 'Reload'),
            onAction: _saving || _loading || !current
                ? null
                : _pendingIds.isNotEmpty
                    ? () => unawaited(_continueSave())
                    : () => unawaited(_load(force: true)),
          ),
        if (persistenceError != null)
          MomentsStatePanel(
            icon: Icons.save_outlined,
            title: momentsText(context,
                zh: '本机选择未能保存',
                en: 'Could not save these choices on this device'),
            message: momentsText(context,
                zh: '权限已保存。重新保存本机记录后，下次打开时仍可查看这些选择。',
                en: 'Your privacy changes were saved. Save these choices on this device to keep them next time.'),
            actionLabel: momentsText(context, zh: '重新保存', en: 'Save again'),
            onAction: canEdit ? () => unawaited(_retryPersistence()) : null,
          ),
        if (!_loading && error == null && _listLoaded && ids.isEmpty)
          Padding(
            padding: MomentsSecondaryLayout.emptyListInset,
            child: Column(children: [
              Semantics(
                label: momentsText(context, zh: '未选取', en: 'None selected'),
                child: Text(
                    momentsText(context,
                        zh: blocked
                            ? '把通讯录的某个朋友放到这里，他（她）将无法看到你发布的朋友圈动态。'
                            : '把通讯录的某个朋友放到这里，你将看不到他（她）发布的朋友圈动态。',
                        en: blocked
                            ? 'Add a contact here. They will not see your moments.'
                            : 'Add a contact here. You will not see their moments in your feed.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: MomentsTheme.secondary(momentsDark(context)),
                        fontSize: MomentsSecondaryLayout.messageSize,
                        height: 1.55)),
              ),
              const SizedBox(height: 28),
              _addButton(canEdit),
            ]),
          ),
        if (ids.isNotEmpty)
          SettingsGroup(margin: EdgeInsets.zero, children: [
            for (var index = 0; index < ids.length; index++)
              SettingsCell(
                title: _friends[ids[index]]?.displayName ?? ids[index],
                leading: AvatarView(
                  width: MomentsLayout.avatarSize,
                  height: MomentsLayout.avatarSize,
                  url: _friends[ids[index]]?.avatarUrl,
                  text: _friends[ids[index]]?.displayName ?? ids[index],
                ),
                showArrow: false,
                showDivider: index < ids.length - 1,
                trailing: IconButton(
                  tooltip: momentsText(context, zh: '移除', en: 'Remove'),
                  onPressed: canEdit
                      ? () => unawaited(_saveEntries([ids[index]], false))
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  color: MomentsTheme.secondary(momentsDark(context)),
                ),
              ),
          ]),
        if (ids.isNotEmpty || _loading || error != null)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: _addButton(canEdit, compact: true)),
        Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: canEdit
                  ? () => unawaited(_pickFriends(enabled: false))
                  : null,
              child: Text(momentsText(context,
                  zh: '选择朋友移除', en: 'Choose friends to remove')),
            )),
        SettingsSectionText(momentsText(context,
            zh: '名单记录在此设备。其他设备设置的朋友也可重新选择并取消。',
            en: 'Shows choices saved on this device. Select a friend to cancel a choice made on another device.')),
      ],
    );
  }
}
