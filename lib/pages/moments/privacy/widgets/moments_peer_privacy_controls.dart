import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../services/moments_repository.dart';
import '../../../mine/settings/widgets/settings_widgets.dart';
import '../../moments_widgets.dart';

/// A contact's choices confirmed on this device, never a complete server ACL.
/// Cross-device choices can also be cancelled in the existing privacy lists.
class MomentsPeerPrivacyControls extends StatefulWidget {
  const MomentsPeerPrivacyControls({
    super.key,
    required this.userId,
    this.repository,
    this.separator,
  });

  final String userId;
  final MomentsRepository? repository;
  final Widget? separator;

  @override
  State<MomentsPeerPrivacyControls> createState() =>
      _MomentsPeerPrivacyControlsState();
}

class _MomentsPeerPrivacyControlsState
    extends State<MomentsPeerPrivacyControls> {
  late MomentsRepository _repository;
  late String _scope;
  int _generation = 0;
  bool _loading = true;
  bool _saving = false;
  bool _ready = false;
  Object? _error;
  Object? _persistenceRetryError;
  MomentsPrivacyChange? _pending;

  bool get _sessionCurrent => _repository.isSessionCurrent(_scope);
  bool get _validPeer =>
      widget.userId.isNotEmpty && widget.userId == widget.userId.trim();
  bool get _featureEnabled =>
      _repository.capabilities?.supportsMoments == true &&
      _repository.capabilities?.settingsEnabled == true;
  bool get _canChange =>
      _sessionCurrent &&
      _validPeer &&
      _ready &&
      _featureEnabled &&
      _repository.privacySelectionsLoaded &&
      !_loading &&
      !_saving &&
      _pending == null;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _repository = widget.repository ?? MomentsRepository.instance;
    _scope = _repository.sessionScope;
    _repository.addListener(_repositoryChanged);
    _loading = true;
    _saving = false;
    _ready = false;
    _error = null;
    _persistenceRetryError = null;
    _pending = null;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant MomentsPeerPrivacyControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.userId != widget.userId) {
      ++_generation;
      _repository.removeListener(_repositoryChanged);
      _bind();
    }
  }

  @override
  void dispose() {
    ++_generation;
    _repository.removeListener(_repositoryChanged);
    super.dispose();
  }

  void _invalidateSession() {
    ++_generation;
    setState(() {
      _ready = false;
      _loading = false;
      _saving = false;
      _pending = null;
      _persistenceRetryError = null;
      _error = const MomentsException('会话已改变，请重新打开资料页',
          code: 'SESSION_CHANGED', authRequired: true);
    });
  }

  void _repositoryChanged() {
    if (!mounted) return;
    if (!_sessionCurrent) {
      // Keep the original scope; an old page cannot resend for the next account.
      _invalidateSession();
    } else {
      setState(() {});
    }
  }

  bool _current(int generation, String scope, String peer,
          MomentsRepository repository) =>
      mounted &&
      generation == _generation &&
      identical(repository, _repository) &&
      peer == widget.userId &&
      scope == _scope &&
      repository.isSessionCurrent(scope);

  void _finish(int generation, {bool loading = false}) {
    if (!mounted || generation != _generation) return;
    if (!_sessionCurrent) {
      _invalidateSession();
      return;
    }
    setState(() {
      if (loading) _loading = false;
      _saving = false;
    });
  }

  Future<void> _load({bool force = false}) async {
    if (!_sessionCurrent) return;
    final generation = ++_generation;
    final scope = _scope;
    final peer = widget.userId;
    final repository = _repository;
    setState(() {
      _loading = true;
      _ready = false;
      _error = null;
    });
    try {
      if (!_validPeer) {
        throw const MomentsException('无法识别联系人', code: 'ArgsError');
      }
      final capabilities = await repository.ensureCapabilities(force: force);
      if (!_current(generation, scope, peer, repository)) return;
      if (!capabilities.supportsMoments || !capabilities.settingsEnabled) {
        throw const MomentsException('朋友圈权限设置尚未开放', unavailable: true);
      }
      // GET settings deliberately cannot hydrate either privacy list.
      await repository.loadPrivacySelections(force: force);
      if (_current(generation, scope, peer, repository)) {
        setState(() => _ready = true);
      }
    } catch (error) {
      if (_current(generation, scope, peer, repository)) {
        setState(() => _error = error);
      }
    } finally {
      _finish(generation, loading: true);
    }
  }

  Future<void> _change(MomentsPrivacyChange change,
      {bool retry = false}) async {
    if (!_sessionCurrent || !_validPeer || _loading || _saving) return;
    if (change.userId != widget.userId || (!retry && !_canChange)) return;
    final generation = ++_generation;
    final scope = _scope;
    final peer = widget.userId;
    final repository = _repository;
    setState(() {
      _pending = change;
      _saving = true;
      _error = null;
      _persistenceRetryError = null;
    });
    try {
      if (retry) {
        final caps = await repository.ensureCapabilities(force: true);
        if (!_current(generation, scope, peer, repository)) return;
        if (!caps.supportsMoments || !caps.settingsEnabled) {
          throw const MomentsException('朋友圈权限设置尚未开放', unavailable: true);
        }
      }
      if (change.kind == MomentsPrivacySelectionKind.blockedViewer) {
        await repository.setBlockedViewer(peer, change.enabled);
      } else {
        await repository.setHiddenAuthor(peer, change.enabled);
      }
      if (_current(generation, scope, peer, repository)) {
        setState(() => _pending = null);
      }
    } catch (error) {
      if (_current(generation, scope, peer, repository)) {
        setState(() => _error = error);
      }
    } finally {
      _finish(generation);
    }
  }

  Future<void> _retryPersistence() async {
    if (!_sessionCurrent || _loading || _saving) return;
    final generation = ++_generation;
    final scope = _scope;
    final peer = widget.userId;
    final repository = _repository;
    setState(() {
      _saving = true;
      _persistenceRetryError = null;
    });
    try {
      await repository.retryPrivacyPersistence();
    } catch (error) {
      if (_current(generation, scope, peer, repository)) {
        setState(() => _persistenceRetryError = error);
      }
    } finally {
      _finish(generation);
    }
  }

  Widget _cell(MomentsPrivacySelectionKind kind, bool selected) {
    final blocked = kind == MomentsPrivacySelectionKind.blockedViewer;
    final title = momentsText(context,
        zh: blocked ? '不让他看我的朋友圈' : '不看他的朋友圈',
        en: blocked ? 'Hide my moments from them' : 'Hide their moments');
    final hint = momentsText(context,
        zh: '仅显示此设备上已确认的选择。其他设备设置可在朋友圈权限名单中取消。',
        en: 'Shows confirmed choices on this device. Cancel choices from other devices in Moments privacy lists.');
    return Tooltip(
      message: hint,
      child: MergeSemantics(
        child: SettingsCell(
          title: title,
          enabled: _canChange,
          showDivider: false,
          showArrow: false,
          trailing: Semantics(
            hint: hint,
            child: _loading
                ? Semantics(
                    value: momentsText(context, zh: '正在读取', en: 'Loading'),
                    liveRegion: true,
                    child: SizedBox.fromSize(
                      size: MomentsLayout.privacyToggleSize,
                      child: const Center(child: CupertinoActivityIndicator()),
                    ),
                  )
                : CupertinoSwitch(
                    key: ValueKey(blocked
                        ? 'moments_peer_blocked_viewer_switch'
                        : 'moments_peer_hidden_author_switch'),
                    value: selected,
                    activeTrackColor: AppTokens.accent,
                    onChanged: _canChange
                        ? (enabled) => unawaited(_change(MomentsPrivacyChange(
                            kind: kind,
                            userId: widget.userId,
                            enabled: enabled)))
                        : null,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _feedback(
          String message, String action, Key key, VoidCallback? retry) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.s5, 0, AppTokens.s5, AppTokens.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(message,
                  style: TextStyle(
                      color:
                          AppTokens.textSecondary(dark: momentsDark(context)),
                      fontSize: AppTokens.captionFontSize)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child:
                  TextButton(key: key, onPressed: retry, child: Text(action)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final current = _sessionCurrent;
    final choices = current && _ready && _repository.privacySelectionsLoaded
        ? _repository.privacySelections
        : MomentsPrivacySelections.empty;
    final error =
        current ? _error : const MomentsException('会话已改变', authRequired: true);
    final persistenceError = current && _repository.privacySelectionsLoaded
        ? _persistenceRetryError ?? _repository.privacyPersistenceError
        : null;
    final canRetry = current && !_loading && !_saving;
    final pending = _pending;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _cell(MomentsPrivacySelectionKind.blockedViewer,
          choices.blockedViewerIds.contains(widget.userId)),
      widget.separator ??
          Divider(
              height: 0,
              indent: AppTokens.s5,
              endIndent: AppTokens.s5,
              color: AppTokens.border(dark: momentsDark(context))),
      _cell(MomentsPrivacySelectionKind.hiddenAuthor,
          choices.hiddenAuthorIds.contains(widget.userId)),
      if (error != null)
        _feedback(
            momentsErrorText(context, error),
            momentsText(context,
                zh: pending == null ? '重新加载' : '重试',
                en: pending == null ? 'Reload' : 'Retry'),
            const ValueKey('moments_peer_privacy_retry'),
            !canRetry
                ? null
                : pending == null
                    ? () => unawaited(_load(force: true))
                    : () => unawaited(_change(pending, retry: true))),
      if (persistenceError != null)
        _feedback(
            momentsText(context,
                zh: '权限已保存，本机记录未能保存。',
                en: 'Privacy was saved. Choices could not be saved on this device.'),
            momentsText(context, zh: '重新保存', en: 'Save again'),
            const ValueKey('moments_peer_privacy_persistence_retry'),
            canRetry ? () => unawaited(_retryPersistence()) : null),
    ]);
  }
}
