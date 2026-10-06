import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import '../../services/moments_repository.dart';
import 'moments_widgets.dart';
import 'presentation/moments_secondary_layout.dart';

typedef MomentsCoverPicker = Future<File?> Function(BuildContext context);

enum _PendingCover { none, upload, settings, reset }

class MomentsCoverPage extends StatefulWidget {
  const MomentsCoverPage({super.key, required this.repository, this.pickImage});
  final MomentsRepository repository;
  final MomentsCoverPicker? pickImage;
  @override
  State<MomentsCoverPage> createState() => _MomentsCoverPageState();
}

class _MomentsCoverPageState extends State<MomentsCoverPage> {
  late final String _scope;
  bool _loading = true, _saving = false, _picking = false;
  bool _versionConflict = false, _versionRefreshed = false;
  _PendingCover _pending = _PendingCover.none;
  Object? _error;
  File? _file;
  String? _fileDigest;
  MomentMedia? _uploaded;
  String _clientMediaId = const Uuid().v4();
  MomentsSettings? _settings;
  bool get _current => widget.repository.isSessionCurrent(_scope);
  bool get _unknown => _pending != _PendingCover.none;
  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
    widget.repository.addListener(_repositoryChanged);
    _load();
  }

  void _repositoryChanged() {
    if (mounted && !_current) {
      _evictPreview();
      setState(() {
        _file = null;
        _fileDigest = null;
        _uploaded = null;
        _settings = null;
        _pending = _PendingCover.none;
        _error = const MomentsException('Session changed', authRequired: true);
      });
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_repositoryChanged);
    _evictPreview();
    super.dispose();
  }

  void _evictPreview() {
    final file = _file;
    if (file != null) unawaited(FileImage(file).evict());
  }

  Future<void> _load() async {
    if (!mounted || !_current) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await widget.repository.loadSettings();
      if (!mounted || !_current) return;
      setState(() {
        _settings = settings;
        if (_versionConflict) {
          _versionConflict = false;
          _versionRefreshed = true;
        }
      });
    } catch (error) {
      if (mounted && _current) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static Future<File?> _defaultPick(BuildContext context) async {
    final assets = await AssetPicker.pickAssets(context,
        pickerConfig: AssetPickerConfig(
          maxAssets: 1,
          requestType: RequestType.image,
          themeColor: AppTokens.accent,
          textDelegate: Localizations.localeOf(context).languageCode == 'zh'
              ? const AssetPickerTextDelegate()
              : const EnglishAssetPickerTextDelegate(),
          selectPredicate: (_, asset, selected) async =>
              selected ||
              const ['image/jpeg', 'image/png', 'image/webp']
                  .contains((await asset.mimeTypeAsync)?.toLowerCase()),
        ));
    if (assets == null || assets.isEmpty) return null;
    final file = await assets.single.file;
    if (file == null) {
      throw const MomentsException('Image unreadable', code: 'IMAGE_INVALID');
    }
    return file;
  }

  Future<void> _pick() async {
    if (_saving || _picking || _unknown || !_current) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await (widget.pickImage ?? _defaultPick)(context);
      if (file == null || !mounted || !_current) return;
      if (!const ['.jpg', '.jpeg', '.png', '.webp']
          .contains(p.extension(file.path).toLowerCase())) {
        throw const MomentsException('Unsupported image',
            code: 'UNSUPPORTED_MEDIA_TYPE');
      }
      if (await file.length() >
          (widget.repository.capabilities?.maxImageBytes ?? 10485760)) {
        throw const MomentsException('Image too large',
            code: 'IMAGE_TOO_LARGE');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw const MomentsException('Image unreadable', code: 'IMAGE_INVALID');
      }
      final digest = sha256.convert(bytes).toString();
      if (!mounted || !_current) return;
      _evictPreview();
      setState(() {
        _file = file;
        _fileDigest = digest;
        _uploaded = null;
        _clientMediaId = const Uuid().v4();
      });
    } catch (error) {
      if (mounted && _current) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  bool _conflict(Object error) =>
      error is MomentsException &&
      (error.statusCode == 409 && error.code.isEmpty ||
          error.code == 'VERSION_CONFLICT' ||
          error.code == 'VERSION_MISMATCH');
  bool _defaultCover(MomentsSettings settings) =>
      (settings.coverMediaId == null || settings.coverMediaId!.isEmpty) &&
      (settings.coverUrl == null || settings.coverUrl!.isEmpty);
  void _finish() {
    if (mounted && _current) Navigator.of(context).pop(true);
  }

  Future<bool> _confirmSetting({required bool reset}) async {
    // A read failure retains the unknown write; it does not prove rejection.
    final latest = await widget.repository.loadSettings();
    if (!mounted || !_current) return true;
    if (reset
        ? _defaultCover(latest)
        : latest.coverMediaId == _uploaded?.mediaId) {
      _finish();
      return true;
    }
    if (latest.version != _settings!.version) {
      setState(() {
        _settings = latest;
        _pending = _PendingCover.none;
        _versionRefreshed = true;
        _error = null;
      });
      // Do not automatically replace a newer cover after reconciliation.
      return true;
    }
    // A read showing the previous version does not prove that the earlier
    // request was rejected. Keep checking without replaying an unknown write.
    setState(() => _error =
        const MomentsException('Result not confirmed', unknownResult: true));
    return true;
  }

  Future<void> _save() async {
    if (_file == null ||
        _saving ||
        _picking ||
        !_current ||
        _settings == null ||
        _versionConflict ||
        _pending == _PendingCover.reset) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    var confirmingSetting = _pending == _PendingCover.settings;
    final confirmingUpload = _pending == _PendingCover.upload;
    var sendingSetting = false;
    var checkingFile = true;
    try {
      if (confirmingSetting && await _confirmSetting(reset: false)) return;
      if (!mounted || !_current) return;
      confirmingSetting = false;
      final bytes = await _file!.readAsBytes();
      if (!mounted || !_current) return;
      if (sha256.convert(bytes).toString() != _fileDigest) {
        throw const MomentsException('Selected file changed',
            code: 'COVER_IMAGE_CHANGED');
      }
      checkingFile = false;
      final justUploaded = _uploaded == null;
      if (justUploaded) {
        _uploaded = await widget.repository.api
            .uploadCover(filePath: _file!.path, clientMediaId: _clientMediaId);
      }
      if (!mounted || !_current) return;
      _pending = _PendingCover.none;
      if (_uploaded!.status == 'FAILED' || _uploaded!.status == 'REJECTED') {
        throw const MomentsException('Cover processing failed',
            code: 'MEDIA_FAILED');
      }
      if (justUploaded && !_uploaded!.isReady) {
        throw const MomentsException('Cover processing pending',
            code: 'MEDIA_PROCESSING');
      }
      sendingSetting = true;
      await widget.repository.updateSettings(
          coverMediaId: _uploaded!.mediaId,
          expectedVersion: _settings!.version);
      if (mounted && _current) _finish();
    } catch (error) {
      if (mounted && _current) {
        setState(() {
          if (confirmingSetting) {
            _pending = _PendingCover.settings;
          } else if (confirmingUpload && checkingFile) {
            _pending = _PendingCover.upload;
          } else if (error is MomentsException && error.unknownResult) {
            _pending = sendingSetting
                ? _PendingCover.settings
                : _uploaded == null
                    ? _PendingCover.upload
                    : _PendingCover.none;
          } else {
            _pending = _PendingCover.none;
          }
          if (_conflict(error)) _versionConflict = true;
          _error = error;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    if (_saving ||
        _picking ||
        _settings == null ||
        !_current ||
        _versionConflict ||
        (_unknown && _pending != _PendingCover.reset)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    var confirming = _pending == _PendingCover.reset;
    try {
      if (confirming && await _confirmSetting(reset: true)) return;
      if (!mounted || !_current) return;
      confirming = false;
      await widget.repository.updateSettings(
          clearCover: true, expectedVersion: _settings!.version);
      _finish();
    } catch (error) {
      if (mounted && _current) {
        setState(() {
          _pending =
              confirming || error is MomentsException && error.unknownResult
                  ? _PendingCover.reset
                  : _PendingCover.none;
          if (_conflict(error)) _versionConflict = true;
          _error = error;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is MomentsException) {
      if (error.code == 'IMAGE_TOO_LARGE') {
        return momentsText(context,
            zh: '图片超过上传大小限制，请选择较小的图片',
            en: 'Choose an image within the upload size limit.');
      }
      if (const [
        'IMAGE_DIMENSIONS_EXCEEDED',
        'IMAGE_INVALID',
        'UNSUPPORTED_MEDIA_TYPE'
      ].contains(error.code)) {
        return momentsText(context,
            zh: '图片尺寸或格式不支持，请选择有效的 JPEG、PNG 或 WebP 图片。',
            en: 'Choose a valid JPEG, PNG or WebP image with supported dimensions.');
      }
      if (const ['MEDIA_FAILED', 'MEDIA_REJECTED'].contains(error.code)) {
        return momentsText(context,
            zh: '封面处理失败，请选择其他图片。',
            en: 'The cover could not be processed. Choose another image.');
      }
      if (const ['MEDIA_PROCESSING', 'MEDIA_NOT_READY'].contains(error.code)) {
        return momentsText(context,
            zh: '封面仍在处理中，请稍后再次保存',
            en: 'The cover is processing. Save again shortly.');
      }
      if (error.code == 'COVER_IMAGE_CHANGED') {
        return momentsText(context,
            zh: _unknown
                ? '所选图片内容已变化。请恢复原图片后确认原任务，确认结果前不能更换图片。'
                : '所选图片内容已变化，请重新选择图片开始新任务。',
            en: _unknown
                ? 'The selected image changed. Restore its original file to confirm the task before choosing another photo.'
                : 'The selected image changed. Choose a photo for a new task.');
      }
      if (_conflict(error)) {
        return momentsText(context,
            zh: '封面设置已被修改，请先刷新最新设置，再决定是否保存。',
            en: 'Cover settings changed. Refresh them, then decide whether to save.');
      }
    }
    return momentsErrorText(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    return PopScope(
        canPop: !_saving && !_picking,
        child: MomentsScaffold(
          title: momentsText(context, zh: '更换封面', en: 'Change cover'),
          body: !_current
              ? MomentsStatePanel(
                  icon: Icons.lock_outline_rounded,
                  title: momentsText(context,
                      zh: '登录状态已改变', en: 'Session changed'),
                  message: momentsText(context,
                      zh: '请重新进入朋友圈，本地预览已关闭。',
                      en: 'Reopen Moments. The local preview has been closed.'))
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _settings == null
                      ? MomentsStatePanel(
                          icon: Icons.photo_outlined,
                          title: momentsText(context,
                              zh: '封面暂不可用', en: 'Cover unavailable'),
                          message: _errorMessage(_error ??
                              const MomentsException('Unavailable',
                                  unavailable: true)),
                          onAction: _load,
                          actionLabel:
                              momentsText(context, zh: '重试', en: 'Retry'))
                      : ListView(
                          padding: const EdgeInsets.all(
                              MomentsSecondaryLayout.pageInset),
                          children: [
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                      MomentsSecondaryLayout.imageRadius),
                                  child: AspectRatio(
                                      aspectRatio: 4 / 3,
                                      child: _file != null
                                          ? Image.file(_file!,
                                              key: const ValueKey(
                                                  'moments_cover_preview'),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Center(
                                                  child: Icon(Icons.broken_image_outlined,
                                                      color: MomentsTheme.secondary(
                                                          dark))))
                                          : _settings!.coverUrl?.isNotEmpty ==
                                                  true
                                              ? MomentsMediaImage(
                                                  repository: widget.repository,
                                                  media: MomentMedia(
                                                      mediaId: 'cover',
                                                      contentPath:
                                                          _settings!.coverUrl!),
                                                  thumbnail: false)
                                              : Image.asset(
                                                  MomentsLayout.coverAsset,
                                                  package: 'openim_common',
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      ColoredBox(color: MomentsTheme.panel(dark), child: const Center(child: Icon(Icons.photo_outlined)))))),
                              const SizedBox(height: AppTokens.s5),
                              Text(
                                  momentsText(context,
                                      zh: '选择一张照片作为朋友圈封面',
                                      en:
                                          'Choose a photo for your Moments cover'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: MomentsTheme.secondary(dark))),
                              const SizedBox(height: AppTokens.s5),
                              OutlinedButton.icon(
                                  key: const ValueKey('moments_cover_pick'),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: MomentsTheme.name(dark),
                                      side: BorderSide(
                                          color: MomentsTheme.border(dark)),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              MomentsSecondaryLayout
                                                  .addButtonRadius))),
                                  onPressed: _saving || _picking || _unknown
                                      ? null
                                      : _pick,
                                  icon:
                                      const Icon(Icons.photo_library_outlined),
                                  label: Text(momentsText(context,
                                      zh: '从手机相册选择',
                                      en: 'Choose from gallery'))),
                              FilledButton(
                                  key: const ValueKey('moments_cover_save'),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: MomentsTheme.name(dark),
                                      foregroundColor: MomentsTheme.card(dark),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              MomentsSecondaryLayout
                                                  .addButtonRadius))),
                                  onPressed: _file == null ||
                                          _saving ||
                                          _picking ||
                                          _versionConflict ||
                                          _pending == _PendingCover.reset
                                      ? null
                                      : _save,
                                  child: _saving || _picking
                                      ? const SizedBox.square(
                                          dimension: AppTokens.s6,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : Text(_unknown
                                          ? momentsText(context,
                                              zh: '确认保存结果', en: 'Confirm save')
                                          : momentsText(context, zh: '保存封面', en: 'Save cover'))),
                              if (_settings!.coverUrl?.isNotEmpty == true ||
                                  _pending == _PendingCover.reset)
                                TextButton(
                                    key: const ValueKey('moments_cover_reset'),
                                    onPressed: _saving ||
                                            _picking ||
                                            _versionConflict ||
                                            (_unknown &&
                                                _pending != _PendingCover.reset)
                                        ? null
                                        : _reset,
                                    child: Text(momentsText(context,
                                        zh: _pending == _PendingCover.reset
                                            ? '确认恢复结果'
                                            : '恢复默认封面',
                                        en: _pending == _PendingCover.reset
                                            ? 'Confirm reset'
                                            : 'Use default cover'))),
                              if (_unknown)
                                Padding(
                                    padding: const EdgeInsets.only(
                                        top: AppTokens.s4),
                                    child: Text(momentsText(context,
                                        zh: '正在核对原任务。确认结果前不能更换图片，以免重复提交。',
                                        en: 'Check the original task before choosing another image to avoid duplicate submissions.'))),
                              if (_versionConflict)
                                TextButton(
                                    key: const ValueKey(
                                        'moments_cover_refresh_version'),
                                    onPressed: _saving ? null : _load,
                                    child: Text(momentsText(context,
                                        zh: '刷新最新设置', en: 'Refresh settings'))),
                              if (_versionRefreshed)
                                Padding(
                                    padding: const EdgeInsets.only(
                                        top: AppTokens.s4),
                                    child: Text(momentsText(context,
                                        zh: '已加载最新设置。所选图片仍保留，是否再次保存由你决定。',
                                        en: 'The latest settings are loaded. Your chosen photo is kept; save again if you want to replace the cover.'))),
                              if (_error != null)
                                Padding(
                                    padding: const EdgeInsets.only(
                                        top: AppTokens.s4),
                                    child: Text(_errorMessage(_error!),
                                        style: const TextStyle(
                                            color: AppTokens.danger))),
                            ]),
        ));
  }
}
