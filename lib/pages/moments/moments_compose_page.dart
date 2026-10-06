import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../services/moments_repository.dart';
import 'moments_draft_store.dart';
import '../mine/settings/widgets/settings_widgets.dart';
import 'moments_privacy_friend_picker.dart';
import 'moments_widgets.dart';
import 'presentation/moments_composer_layout.dart';
import 'presentation/moments_composer_media_grid.dart';
import 'presentation/moments_composer_media_tile.dart';
import 'presentation/moments_secondary_layout.dart';

typedef MomentsImagePicker = Future<List<File>> Function(
    BuildContext context, int remaining);

class MomentsComposePage extends StatefulWidget {
  const MomentsComposePage(
      {super.key,
      this.repository,
      this.draftStore,
      this.displayName,
      this.avatarUrl,
      this.pickImages});
  final MomentsRepository? repository;
  final MomentsDraftStore? draftStore;
  final String? displayName;
  final String? avatarUrl;
  final MomentsImagePicker? pickImages;
  @override
  State<MomentsComposePage> createState() => _MomentsComposePageState();
}

class _MomentsComposePageState extends State<MomentsComposePage>
    with WidgetsBindingObserver {
  late final MomentsRepository _repository;
  late final MomentsDraftStore _store;
  final _text = TextEditingController();
  Timer? _saveTimer;
  MomentsCapabilities? _capabilities;
  Object? _serviceError;
  Object? _pickerError;
  Object? _leaveError;
  bool _checkingCapabilities = true;
  bool _capabilitiesRequestRunning = false;
  bool _picking = false;
  bool _restoringText = false;
  bool _leaving = false;
  bool _allowPop = false;
  bool _popScheduled = false;
  bool _publishing = false;
  DialogRoute<String>? _leaveDialogRoute;
  int get _maxImages => (_capabilities?.maxImages ?? 9).clamp(0, 9);
  int get _maxText => _capabilities?.maxTextLength ?? 2000;
  bool get _editable =>
      _store.loaded &&
      !_store.recoveryFailed &&
      !_store.frozen &&
      !_picking &&
      !_leaving &&
      !_popScheduled &&
      _store.sessionCurrent;
  bool get _canPublish =>
      _store.loaded &&
      !_store.recoveryFailed &&
      _store.sessionCurrent &&
      !_publishing &&
      !_leaving &&
      !_popScheduled &&
      !_store.busy &&
      !_picking &&
      _store.persistenceError == null &&
      _capabilities?.publishEnabled == true &&
      _store.hasContent &&
      _text.text.trim().runes.length <= _maxText &&
      (!_store.visibility.requiresAudience ||
          _store.visibility.audienceUserIds.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ??
        widget.draftStore?.repository ??
        MomentsRepository.instance;
    _store = widget.draftStore ?? MomentsDraftStore.forRepository(_repository);
    WidgetsBinding.instance.addObserver(this);
    _store.addListener(_storeChanged);
    _text.addListener(_textChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    await _store.load();
    if (!mounted) return;
    _restoringText = true;
    _text.text = _store.text;
    _restoringText = false;
    await _checkCapabilities();
  }

  Future<void> _checkCapabilities() async {
    if (_capabilitiesRequestRunning) return;
    _capabilitiesRequestRunning = true;
    if (mounted) {
      setState(() {
        _checkingCapabilities = true;
        _serviceError = null;
      });
    }
    try {
      final caps = await _repository.ensureCapabilities(force: true);
      if (!mounted || !_store.sessionCurrent) return;
      setState(() => _capabilities = caps);
    } catch (e) {
      if (mounted) {
        setState(() {
          _capabilities = null;
          _serviceError = e;
        });
      }
    } finally {
      _capabilitiesRequestRunning = false;
      if (mounted) setState(() => _checkingCapabilities = false);
    }
  }

  void _storeChanged() {
    if (mounted) setState(() {});
  }

  void _textChanged() {
    if (_restoringText || !_editable) return;
    _store.updateText(_text.text);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _save);
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    if (!_store.loaded || _store.recoveryFailed) return;
    try {
      await _store.save();
    } catch (_) {/* The store exposes a persistent save error. */}
    if (mounted) setState(() {});
  }

  Future<void> _retryRecovery() async {
    if (!_store.loaded || !_store.sessionCurrent) return;
    await _store.retryRecovery();
    if (!mounted || !_store.sessionCurrent || _store.recoveryFailed) return;
    _restoringText = true;
    _text.text = _store.text;
    _restoringText = false;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _save();
    }
    if (state == AppLifecycleState.resumed && !_store.busy) {
      _checkCapabilities();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _save();
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_storeChanged);
    _text.dispose();
    // The account-owned publish worker survives this route.
    super.dispose();
  }

  static Future<List<File>> _pickImages(
      BuildContext context, int remaining) async {
    final assets = await AssetPicker.pickAssets(context,
        pickerConfig: AssetPickerConfig(
          requestType: RequestType.image,
          maxAssets: remaining,
          selectPredicate: (_, asset, selected) async {
            if (selected) return true;
            final type = await asset.mimeTypeAsync;
            return const ['image/jpeg', 'image/png', 'image/webp']
                .contains(type?.toLowerCase());
          },
        ));
    if (assets == null) return const [];
    final files = <File>[];
    for (final asset in assets) {
      final file = await asset.file;
      if (file == null) {
        throw const FileSystemException('Could not read selected image');
      }
      files.add(file);
    }
    return files;
  }

  Future<void> _addImages() async {
    if (!_editable || _store.media.length >= _maxImages) return;
    setState(() {
      _picking = true;
      _pickerError = null;
    });
    try {
      final files = await (widget.pickImages ?? _pickImages)(
          context, _maxImages - _store.media.length);
      if (!mounted || !_store.sessionCurrent) return;
      await _store.addFiles(files, maxImages: _maxImages);
    } catch (e) {
      if (mounted) setState(() => _pickerError = e);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _visibility() async {
    if (!_editable) return;
    final mode = await showSettingsActionSheet<String>(
      context,
      title: momentsText(context, zh: '谁可以看', en: 'Who can see this'),
      actions: [
        SettingsAction(momentsText(context, zh: '公开', en: 'Public'), 'FRIENDS',
            subtitle: momentsText(context,
                zh: '所有好友可见', en: 'Visible to all friends')),
        SettingsAction(
            momentsText(context, zh: '不给谁看', en: 'Exclude friends'), 'EXCLUDE'),
        SettingsAction(momentsText(context, zh: '部分可见', en: 'Selected friends'),
            'PARTIAL'),
        SettingsAction(momentsText(context, zh: '仅自己', en: 'Only me'), 'SELF'),
      ],
    );
    if (mode == null || !mounted || !_editable || !_store.sessionCurrent) {
      return;
    }
    var selection = MomentsVisibilitySelection(mode: mode);
    if (selection.requiresAudience) {
      final users =
          await Navigator.of(context).push<List<MomentUser>>(MaterialPageRoute(
        builder: (_) => MomentsPrivacyFriendPicker(
          repository: _repository,
          title: momentsText(context,
              zh: mode == 'EXCLUDE' ? '不给谁看' : '部分可见',
              en: mode == 'EXCLUDE' ? 'Exclude friends' : 'Selected friends'),
          initialSelectedIds: _store.visibility.audienceUserIds,
        ),
      ));
      if (users == null ||
          users.isEmpty ||
          !mounted ||
          !_editable ||
          !_store.sessionCurrent) {
        return;
      }
      selection = MomentsVisibilitySelection(
          mode: mode,
          audienceUserIds:
              users.map((user) => user.userId).toList(growable: false));
    }
    try {
      await _store.updateVisibility(selection);
    } catch (_) {/* Save error is visible on the page. */}
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    setState(() => _publishing = true);
    FocusManager.instance.primaryFocus?.unfocus();
    _saveTimer?.cancel();
    try {
      final post = await _store.publish();
      if (!mounted ||
          !_store.sessionCurrent ||
          (post == null && _store.confirmedMomentId == null)) {
        return;
      }
      if (post?.status == 'PENDING_REVIEW') {
        IMViews.showToast(
            momentsText(context, zh: '已提交，等待审核', en: 'Submitted for review'));
      }
      _pop(post);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _pop([MomentPost? post]) {
    if (!mounted || _popScheduled) return;
    _popScheduled = true;
    final navigator = Navigator.of(context);
    final pageRoute = ModalRoute.of(context);
    final dialog = _leaveDialogRoute;
    if (dialog?.isActive == true) {
      // A publish result closes only this page's confirmation, never an
      // unrelated route; keep the dialog's result type intact.
      navigator.removeRoute(dialog!, 'published');
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (pageRoute?.isCurrent != false) {
        navigator.pop(post);
      } else {
        _popScheduled = false;
        setState(() => _allowPop = false);
      }
    });
  }

  Future<void> _leave() async {
    if (_leaving || _picking || _popScheduled) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_store.recoveryFailed ||
        !_store.loaded ||
        (!_store.hasContent && !_store.frozen)) {
      _pop();
      return;
    }
    setState(() {
      _leaving = true;
      _leaveError = null;
    });
    final uncertain = _store.resultUncertain;
    final dialog = DialogRoute<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(
                  momentsText(context, zh: '离开发布页？', en: 'Leave this post?')),
              content: Text(uncertain
                  ? momentsText(context,
                      zh: '发布结果仍在确认中。任务会保留，下次回来继续核对，避免重复发布。',
                      en:
                          'The publish result is still being confirmed. Keep this task and check it again when you return.')
                  : momentsText(context,
                      zh: _store.busy ? '上传会继续进行，草稿和任务会保留。' : '可保存草稿，下次继续编辑。',
                      en: _store.busy
                          ? 'Uploads can continue. Your draft and task will be kept.'
                          : 'Save your draft and finish it later.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop('stay'),
                    child: Text(momentsText(context, zh: '继续编辑', en: 'Stay'))),
                if (!uncertain)
                  TextButton(
                      key: const ValueKey('moments_discard'),
                      onPressed: () =>
                          Navigator.of(dialogContext).pop('discard'),
                      child: Text(
                          momentsText(context, zh: '放弃草稿', en: 'Discard draft'),
                          style: const TextStyle(color: AppTokens.danger))),
                FilledButton(
                    key: const ValueKey('moments_save_leave'),
                    onPressed: () => Navigator.of(dialogContext).pop('save'),
                    child: Text(momentsText(context,
                        zh: '保存并离开', en: 'Save and leave'))),
              ],
            ));
    _leaveDialogRoute = dialog;
    try {
      final choice = await Navigator.of(context).push<String>(dialog);
      if (!mounted ||
          choice == null ||
          choice == 'stay' ||
          choice == 'published' ||
          _popScheduled) {
        return;
      }
      _saveTimer?.cancel();
      if (choice == 'discard') {
        await _store.discard();
      } else {
        await _store.save();
      }
      if (mounted) _pop();
    } catch (e) {
      if (mounted) setState(() => _leaveError = e);
    } finally {
      if (_leaveDialogRoute == dialog) _leaveDialogRoute = null;
      if (mounted) setState(() => _leaving = false);
    }
  }

  String _visibilityLabel() => switch (_store.visibility.mode) {
        'SELF' => momentsText(context, zh: '仅自己', en: 'Only me'),
        'PARTIAL' => momentsText(context,
            zh: '部分好友（${_store.visibility.audienceUserIds.length}）',
            en: 'Selected friends (${_store.visibility.audienceUserIds.length})'),
        'EXCLUDE' => momentsText(context,
            zh: '不给谁看（${_store.visibility.audienceUserIds.length}）',
            en: 'Excluded friends (${_store.visibility.audienceUserIds.length})'),
        _ => momentsText(context, zh: '公开', en: 'Public'),
      };
  String _stageText() => switch (_store.stage) {
        MomentsPublishStage.preparing =>
          momentsText(context, zh: '正在准备图片…', en: 'Preparing images…'),
        MomentsPublishStage.uploading =>
          momentsText(context, zh: '正在上传图片…', en: 'Uploading images…'),
        MomentsPublishStage.readyToCommit =>
          momentsText(context, zh: '图片已准备好', en: 'Images are ready'),
        MomentsPublishStage.submitting =>
          momentsText(context, zh: '正在提交动态…', en: 'Submitting your post…'),
        MomentsPublishStage.submitUnknown => momentsText(context,
            zh: '发布结果待确认', en: 'Confirming the publish result'),
        MomentsPublishStage.uploadFailed => momentsText(context,
            zh: '上传未完成，草稿已保留', en: 'Upload incomplete. Your draft is kept'),
        MomentsPublishStage.submitFailed => momentsText(context,
            zh: '发布未通过，请调整内容', en: 'Post rejected. Review your content'),
        MomentsPublishStage.awaitingAuth =>
          momentsText(context, zh: '请恢复登录后继续', en: 'Sign in again to continue'),
        _ =>
          momentsText(context, zh: '草稿自动保存', en: 'Draft saves automatically'),
      };
  String _publishLabel() => _store.busy
      ? momentsText(context, zh: '处理中', en: 'Working…')
      : _store.resultUncertain
          ? momentsText(context, zh: '核对结果', en: 'Check result')
          : _store.job != null
              ? momentsText(context, zh: '重试', en: 'Retry')
              : momentsText(context, zh: '发布', en: 'Post');

  Widget _banner(
      {required IconData icon, required String message, Widget? action}) {
    final dark = momentsDark(context);
    return Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.s4),
        child: Material(
          color: AppTokens.surfaceAlt(dark: dark),
          borderRadius: BorderRadius.circular(AppTokens.rMd),
          child: Padding(
              padding: const EdgeInsets.all(AppTokens.s4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon,
                              color: AppTokens.textSecondary(dark: dark)),
                          const SizedBox(width: AppTokens.s3),
                          Expanded(
                              child: Text(message,
                                  style: TextStyle(
                                      color:
                                          AppTokens.textPrimary(dark: dark)))),
                        ]),
                    if (action != null)
                      Align(alignment: Alignment.centerRight, child: action),
                  ])),
        ));
  }

  Future<void> _mediaAction(MomentsDraftMedia media, String action) async {
    if (!_editable) return;
    final index = _store.media.indexOf(media);
    try {
      if (action == 'remove') await _store.removeMedia(media.clientMediaId);
      if (action == 'earlier') {
        await _store.moveMedia(media.clientMediaId, index - 1);
      }
      if (action == 'later') {
        await _store.moveMedia(media.clientMediaId, index + 1);
      }
    } catch (e) {
      if (mounted) setState(() => _pickerError = e);
    }
  }

  void _preview(int index) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MediaBrowser(
          sources: _store.media
              .map((item) =>
                  MediaSource(thumbnail: item.path, file: File(item.path)))
              .toList(),
          initialIndex: index,
          showGallery: false)));
  Widget _mediaTile(MomentsDraftMedia item, int index) =>
      MomentsComposerMediaTile(
        media: item,
        index: index,
        imageCount: _store.media.length,
        editable: _editable,
        frozen: _store.frozen,
        onPreview: () => _preview(index),
        onAction: (action) => _mediaAction(item, action),
        onMove: (clientMediaId) async {
          if (!_editable) return;
          try {
            await _store.moveMedia(clientMediaId, index);
          } catch (e) {
            if (mounted) setState(() => _pickerError = e);
          }
        },
      );
  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    final name = widget.displayName?.trim().isNotEmpty == true
        ? widget.displayName!
        : momentsText(context, zh: '我', en: 'Me');
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: MomentsTheme.detailBackground(dark),
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          backgroundColor: MomentsTheme.card(dark),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
              key: const ValueKey('moments_compose_close'),
              tooltip: momentsText(context, zh: '关闭', en: 'Close'),
              onPressed: _picking ? null : _leave,
              icon: const Icon(Icons.close_rounded),
              color: MomentsTheme.nav(dark)),
          title: Text(momentsText(context, zh: '发动态', en: 'New post'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: MomentsTheme.text(dark),
                  fontSize: MomentsSecondaryLayout.titleSize,
                  fontWeight: FontWeight.w600)),
          actions: [
            TextButton(
                key: const ValueKey('moments_publish'),
                onPressed: _canPublish &&
                        _store.stage != MomentsPublishStage.submitFailed
                    ? _publish
                    : null,
                style: TextButton.styleFrom(
                    foregroundColor: MomentsTheme.name(dark),
                    disabledForegroundColor: MomentsTheme.secondary(dark)),
                child: Text(_publishLabel(),
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        body: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: MomentsLayout.pageMaxWidth),
                child: !_store.sessionCurrent
                    ? MomentsStatePanel(
                        icon: Icons.lock_outline_rounded,
                        title: momentsText(context,
                            zh: '登录状态已改变', en: 'Session changed'),
                        message: momentsText(context,
                            zh: '请重新进入朋友圈，草稿按原账号保存。',
                            en:
                                'Reopen Moments. Your draft is kept for its original account.'))
                    : !_store.loaded
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                            key: const ValueKey('moments_compose_scroll'),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.all(
                                MomentsSecondaryLayout.pageInset),
                            children: [
                                if (!_store.sessionCurrent)
                                  _banner(
                                      icon: Icons.lock_outline_rounded,
                                      message: momentsText(context,
                                          zh: '登录状态已改变，请退出后重新进入。',
                                          en: 'Your session changed. Reopen this page to continue.')),
                                if (_checkingCapabilities)
                                  const LinearProgressIndicator()
                                else if (_serviceError != null ||
                                    _capabilities?.publishEnabled != true)
                                  _banner(
                                      icon: Icons.cloud_off_outlined,
                                      message: _serviceError != null
                                          ? momentsErrorText(
                                              context, _serviceError!)
                                          : momentsText(context,
                                              zh: '发布服务尚未开放，可先保存草稿。',
                                              en:
                                                  'Publishing is not available yet. You can save a draft.'),
                                      action: TextButton(
                                          onPressed: _checkCapabilities,
                                          child: Text(momentsText(context,
                                              zh: '重新检查', en: 'Check again')))),
                                if (_store.recoveryFailed)
                                  _banner(
                                      icon: Icons.restore_rounded,
                                      message: momentsText(context,
                                          zh: '草稿暂时无法读取，请重新读取后继续。',
                                          en:
                                              'Could not read your draft. Read it again to continue.'),
                                      action: TextButton(
                                          key: const ValueKey(
                                              'moments_retry_recovery'),
                                          onPressed: _retryRecovery,
                                          child: Text(momentsText(context,
                                              zh: '重新读取', en: 'Read again'))))
                                else if (_store.persistenceError != null)
                                  _banner(
                                      icon: Icons.save_outlined,
                                      message: momentsText(context,
                                          zh: '草稿保存失败，请重试后再发布或离开。',
                                          en:
                                              'Could not save your draft. Retry before posting or leaving.'),
                                      action: TextButton(
                                          onPressed: _save,
                                          child: Text(momentsText(context,
                                              zh: '重试保存',
                                              en: 'Retry saving')))),
                                if (_pickerError != null)
                                  _banner(
                                      icon: Icons.image_not_supported_outlined,
                                      message: momentsText(context,
                                          zh: '图片处理失败，请检查相册权限、文件和储存空间。',
                                          en: 'Could not prepare images. Check photo access, files and storage.')),
                                if (_leaveError != null &&
                                    _store.persistenceError == null)
                                  _banner(
                                      icon: Icons.save_outlined,
                                      message: momentsText(context,
                                          zh: '草稿操作未完成，请稍后重试。',
                                          en: 'Could not finish this draft action. Try again shortly.')),
                                MomentsComposerLayout(
                                  name: name,
                                  avatarUrl: widget.avatarUrl,
                                  controller: _text,
                                  editable: _editable,
                                  maxText: _maxText,
                                  visibilityLabel: _visibilityLabel(),
                                  onVisibility: _editable ? _visibility : null,
                                  onPickPhotos: _editable &&
                                          _store.media.length < _maxImages
                                      ? _addImages
                                      : null,
                                  picking: _picking,
                                  media: _store.media.isEmpty
                                      ? null
                                      : MomentsComposerMediaGrid(
                                          paths: _store.media
                                              .map((item) => item.path)
                                              .toList(),
                                          itemBuilder: (_, index) => _mediaTile(
                                              _store.media[index], index)),
                                  status: Text(
                                      _store.recoveryFailed
                                          ? momentsText(context,
                                              zh: '原草稿仍保留',
                                              en: 'Your original draft is kept')
                                          : _stageText(),
                                      style: TextStyle(
                                          color: MomentsTheme.secondary(dark),
                                          fontSize: MomentsSecondaryLayout
                                              .draftSize)),
                                ),
                                const SizedBox(
                                    height: MomentsSecondaryLayout.avatarGap),
                                if (_store.resultUncertain)
                                  Padding(
                                      padding: const EdgeInsets.only(
                                          top: AppTokens.s3),
                                      child: Text(momentsText(context,
                                          zh: '内容已冻结。先核对原任务结果，避免重复发布。',
                                          en: 'Content is locked while the original request is checked to prevent duplicate posts.'))),
                                if (_store.busy && _store.media.isNotEmpty)
                                  Padding(
                                      padding: const EdgeInsets.only(
                                          top: AppTokens.s4),
                                      child: LinearProgressIndicator(
                                          value: _store.media.fold<double>(
                                                  0,
                                                  (sum, m) =>
                                                      sum + m.progress) /
                                              _store.media.length)),
                                if (_store.error != null)
                                  Padding(
                                      padding: const EdgeInsets.only(
                                          top: AppTokens.s4),
                                      child: Text(
                                          momentsErrorText(
                                              context, _store.error!),
                                          style: const TextStyle(
                                              color: AppTokens.danger))),
                                if (_store.frozen &&
                                    !_store.resultUncertain &&
                                    !_store.busy)
                                  Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                          key: const ValueKey(
                                              'moments_resume_editing'),
                                          onPressed: _store.resumeEditing,
                                          child: Text(momentsText(context,
                                              zh: '继续编辑草稿',
                                              en: 'Edit draft')))),
                                const SizedBox(height: AppTokens.s7),
                              ]),
              ),
            )),
      ),
    );
  }
}
