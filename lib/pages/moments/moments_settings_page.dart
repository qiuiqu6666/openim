import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../services/moments_repository.dart';
import '../mine/settings/widgets/settings_widgets.dart';
import 'moments_privacy_list_page.dart';
import 'moments_widgets.dart';

class MomentsSettingsPage extends StatefulWidget {
  const MomentsSettingsPage({super.key, required this.repository});

  final MomentsRepository repository;

  @override
  State<MomentsSettingsPage> createState() => _MomentsSettingsPageState();
}

class _MomentsSettingsPageState extends State<MomentsSettingsPage> {
  MomentsSettings? _settings;
  bool _loading = true;
  bool _saving = false;
  bool _choosingRange = false;
  bool _openingList = false;
  Object? _error;
  Object? _privacyError;
  Object? _persistenceRetryError;
  bool _errorFromSave = false;
  int _requestGeneration = 0;
  late String _scope;

  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
    widget.repository.addListener(_repositoryChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant MomentsSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.removeListener(_repositoryChanged);
      widget.repository.addListener(_repositoryChanged);
      _scope = widget.repository.sessionScope;
      _settings = null;
      _privacyError = null;
      _persistenceRetryError = null;
      _saving = false;
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
      _scope = widget.repository.sessionScope;
      setState(() {
        _settings = null;
        _privacyError = null;
        _persistenceRetryError = null;
        _loading = false;
        _saving = false;
        _error = const MomentsException('会话已改变，请重新打开朋友圈', authRequired: true);
      });
      return;
    }
    setState(() {
      if (_settings != null && widget.repository.settings != null) {
        _settings = widget.repository.settings;
      }
    });
  }

  Future<void> _load() async {
    final request = ++_requestGeneration;
    final repository = widget.repository;
    final scope = _scope;
    setState(() {
      _loading = true;
      _error = null;
      _privacyError = null;
      _errorFromSave = false;
    });
    try {
      final settings = await repository.loadSettings();
      if (!mounted ||
          request != _requestGeneration ||
          widget.repository != repository ||
          !repository.isSessionCurrent(scope)) {
        return;
      }
      setState(() => _settings = settings);
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        setState(() {
          _error = error;
          _errorFromSave = false;
        });
      }
    }
    if (!mounted ||
        request != _requestGeneration ||
        widget.repository != repository ||
        !repository.isSessionCurrent(scope)) {
      return;
    }
    try {
      await repository.loadPrivacySelections();
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        setState(() => _privacyError = error);
      }
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  String _rangeLabel(int days) => switch (days) {
        0 => momentsText(context, zh: '全部', en: 'All'),
        3 => momentsText(context, zh: '最近三天', en: 'Last 3 days'),
        90 => momentsText(context, zh: '最近三个月', en: 'Last 3 months'),
        180 => momentsText(context, zh: '最近半年', en: 'Last 6 months'),
        365 => momentsText(context, zh: '最近一年', en: 'Last year'),
        _ => momentsText(context, zh: '未设置', en: 'Not set'),
      };

  Future<void> _pickRange() async {
    final settings = _settings;
    if (settings == null || _saving || _loading || _choosingRange) return;
    _choosingRange = true;
    final scope = _scope;
    final request = _requestGeneration;
    final selected = await showSettingsActionSheet<int>(
      context,
      title: momentsText(context,
          zh: '允许朋友查看朋友圈的范围', en: 'Visible range for friends'),
      actions: [
        for (final days in [0, 3, 90, 180, 365])
          SettingsAction(_rangeLabel(days), days,
              enabled: days != settings.visibleRangeDays),
      ],
    );
    _choosingRange = false;
    if (!mounted ||
        selected == null ||
        !widget.repository.isSessionCurrent(scope) ||
        request != _requestGeneration) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.repository.updateSettings(
        visibleRangeDays: selected,
        expectedVersion: settings.version,
      );
      if (mounted && request == _requestGeneration) {
        setState(() => _settings = updated);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(momentsText(context, zh: '已保存', en: 'Saved'))));
      }
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        setState(() {
          _error = error;
          _errorFromSave = true;
        });
      }
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openList(MomentsPrivacyKind kind) async {
    if (_openingList || _loading || _saving) return;
    _openingList = true;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) =>
          MomentsPrivacyListPage(repository: widget.repository, kind: kind),
    ));
    _openingList = false;
    if (mounted) await _load();
  }

  String _selectionLabel(List<String> ids) {
    if (!widget.repository.privacySelectionsLoaded) return '…';
    return ids.isEmpty
        ? momentsText(context, zh: '未选取', en: 'None selected')
        : momentsText(context,
            zh: '${ids.length} 人',
            en: '${ids.length} ${ids.length == 1 ? 'friend' : 'friends'}');
  }

  Future<void> _retryPrivacyPersistence() async {
    if (_saving || _loading) return;
    final scope = _scope;
    final request = _requestGeneration;
    setState(() {
      _saving = true;
      _persistenceRetryError = null;
    });
    try {
      await widget.repository.retryPrivacyPersistence();
    } catch (error) {
      if (mounted &&
          request == _requestGeneration &&
          widget.repository.isSessionCurrent(scope)) {
        setState(() => _persistenceRetryError = error);
      }
    } finally {
      if (mounted &&
          request == _requestGeneration &&
          widget.repository.isSessionCurrent(scope)) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final error = _error;
    final unavailable = error is MomentsException && error.unavailable;
    final choices = widget.repository.privacySelections;
    final persistenceError = widget.repository.privacySelectionsLoaded
        ? _persistenceRetryError ?? widget.repository.privacyPersistenceError
        : null;
    return SettingsScaffold(
      title: momentsText(context, zh: '朋友圈权限', en: 'Moments privacy'),
      children: [
        if (_loading && settings == null)
          const Padding(
            padding: EdgeInsets.all(AppTokens.s8),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        if (error != null)
          MomentsStatePanel(
            icon: unavailable
                ? Icons.info_outline_rounded
                : Icons.cloud_off_rounded,
            title: momentsText(
              context,
              zh: unavailable
                  ? '朋友圈尚未开放'
                  : _errorFromSave
                      ? '设置未能完成'
                      : '设置加载失败',
              en: unavailable
                  ? 'Moments is not available yet'
                  : _errorFromSave
                      ? 'Could not update settings'
                      : 'Could not load settings',
            ),
            message: momentsErrorText(context, error),
            actionLabel: momentsText(context, zh: '重新加载', en: 'Reload'),
            onAction: _saving || _loading ? null : () => unawaited(_load()),
          ),
        if (settings != null)
          SettingsGroup(
            margin: EdgeInsets.zero,
            children: [
              SettingsCell(
                title: momentsText(context,
                    zh: '不让他（她）看', en: 'Hide my posts from'),
                value: _selectionLabel(choices.blockedViewerIds),
                enabled: !_loading && !_saving,
                onTap: () =>
                    unawaited(_openList(MomentsPrivacyKind.blockedViewer)),
              ),
              SettingsCell(
                title:
                    momentsText(context, zh: '不看他（她）', en: 'Hide their posts'),
                value: _selectionLabel(choices.hiddenAuthorIds),
                enabled: !_loading && !_saving,
                onTap: () =>
                    unawaited(_openList(MomentsPrivacyKind.hiddenAuthor)),
              ),
              SettingsCell(
                title: momentsText(context,
                    zh: '允许朋友查看朋友圈的范围', en: 'Visible range for friends'),
                value: _rangeLabel(settings.visibleRangeDays),
                trailing: _saving ? const CupertinoActivityIndicator() : null,
                enabled: !_loading && !_saving,
                showDivider: false,
                onTap: _pickRange,
              ),
            ],
          ),
        if (_privacyError != null)
          MomentsStatePanel(
            icon: Icons.cloud_off_rounded,
            title: momentsText(context,
                zh: '本机选择加载失败', en: 'Could not load choices on this device'),
            message: momentsErrorText(context, _privacyError!),
            actionLabel: momentsText(context, zh: '重新加载', en: 'Reload'),
            onAction: _saving || _loading ? null : () => unawaited(_load()),
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
            onAction: _saving || _loading
                ? null
                : () => unawaited(_retryPrivacyPersistence()),
          ),
        if (settings != null)
          SettingsSectionText(momentsText(context,
              zh: '人数为此设备上已设置的朋友。',
              en: 'Counts show friends set on this device.')),
      ],
    );
  }
}
