import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/favorite_repository.dart';
import '../../mine/settings/widgets/settings_widgets.dart';
import 'favorite_audio_preview.dart';
import 'favorite_preview_loader.dart';

class FavoriteAssetPreview extends StatefulWidget {
  const FavoriteAssetPreview(
      {super.key,
      required this.repository,
      required this.item,
      required this.asset,
      this.loaderFactory});
  final FavoriteRepository repository;
  final FavoriteItem item;
  final FavoriteAsset asset;
  final FavoritePreviewLoader Function()? loaderFactory;
  @override
  State<FavoriteAssetPreview> createState() => _FavoriteAssetPreviewState();
}

class _FavoriteAssetPreviewState extends State<FavoriteAssetPreview>
    with WidgetsBindingObserver {
  late final String _scope;
  FavoritePreviewLoader? _loader;
  File? _file;
  Uint8List? _bytes;
  bool _loading = true, _invalid = false, _foreground = true;
  bool _requestInFlight = false;
  double? _progress;
  String? _error;
  bool get _current => !_invalid && widget.repository.isSessionCurrent(_scope);
  bool get _isAudio => widget.asset.mimeType.startsWith('audio/');
  Duration? get _audioDuration => widget.asset.durationMs == null
      ? null
      : Duration(milliseconds: widget.asset.durationMs!);

  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
    widget.repository.addListener(_checkSession);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  void _checkSession() {
    if (mounted && !_current && !_invalid) {
      _evict();
      setState(() {
        _invalid = true;
        _file = null;
        _bytes = null;
      });
      unawaited(_loader?.close());
    }
  }

  void _evict() {
    if (_bytes != null) unawaited(MemoryImage(_bytes!).evict());
  }

  Future<void> _load() async {
    if (!_current || _requestInFlight) return;
    _requestInFlight = true;
    setState(() {
      _loading = true;
      _progress = null;
      _error = null;
    });
    await _loader?.close();
    if (!mounted || !_current) return;
    final loader = widget.loaderFactory?.call() ?? FavoritePreviewLoader();
    _loader = loader;
    try {
      final file = await loader
          .load(widget.repository, widget.item, widget.asset, _scope,
              onProgress: (received, total) {
        if (mounted && _current && identical(_loader, loader)) {
          setState(() =>
              _progress = total > 0 ? (received / total).clamp(0, 1) : null);
        }
      });
      final bytes = widget.asset.mimeType.startsWith('image/')
          ? await file.readAsBytes()
          : null;
      if (!mounted || !_current || !identical(_loader, loader)) return;
      setState(() {
        _file = file;
        _bytes = bytes;
      });
    } catch (error) {
      if (mounted && _current) {
        setState(() => _error = error is FavoriteApiException
            ? error.message
            : settingsText(context,
                zh: '原件加载失败，请重试预览',
                en: 'Could not load the original. Retry the preview.'));
      }
    } finally {
      _requestInFlight = false;
      if (mounted && _current) setState(() => _loading = false);
    }
  }

  Future<void> _imageFullscreen() async {
    final bytes = _bytes;
    if (!_current || bytes == null) return;
    await showDialog<void>(
        context: context,
        useSafeArea: true,
        builder: (dialogContext) => AnimatedBuilder(
            animation: widget.repository,
            builder: (_, __) => Dialog.fullscreen(
                backgroundColor: AppTokens.backgroundDark,
                child: Stack(children: [
                  Positioned.fill(
                      child: _current
                          ? AdaptiveMediaImage(
                              image: MemoryImage(bytes),
                              enableSlideOutPage: false,
                            )
                          : const Center(
                              child: Icon(Icons.lock_outline,
                                  color: AppTokens.textPrimaryDark))),
                  Positioned(
                      top: AppTokens.s4,
                      right: AppTokens.s4,
                      child: IconButton(
                          key: const ValueKey('favorite-image-close'),
                          tooltip: settingsText(dialogContext,
                              zh: '关闭图片预览', en: 'Close image preview'),
                          color: AppTokens.textPrimaryDark,
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close))),
                ]))));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_checkSession);
    WidgetsBinding.instance.removeObserver(this);
    _evict();
    unawaited(_loader?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_invalid) return const SizedBox.shrink();
    if (_loading) {
      if (_isAudio) {
        return FavoriteAudioPreview.placeholder(
          title: widget.asset.fileName,
          fileSizeBytes: widget.asset.sizeBytes,
          durationHint: _audioDuration,
          progress: _progress,
        );
      }
      return Padding(
          padding: const EdgeInsets.all(AppTokens.s5),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(value: _progress),
            const SizedBox(height: AppTokens.s3),
            Text(settingsText(context, zh: '正在加载原件', en: 'Loading original')),
          ]));
    }
    if (_error != null) {
      if (_isAudio) {
        return KeyedSubtree(
          key: ValueKey('favorite-preview-retry-${widget.asset.id}'),
          child: FavoriteAudioPreview.placeholder(
            title: widget.asset.fileName,
            fileSizeBytes: widget.asset.sizeBytes,
            durationHint: _audioDuration,
            error: _error,
            onRetry: () => unawaited(_load()),
          ),
        );
      }
      return TextButton.icon(
          key: ValueKey('favorite-preview-retry-${widget.asset.id}'),
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(_error!));
    }
    if (_bytes != null) {
      return Column(children: [
        ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: InteractiveViewer(
                child: Image.memory(_bytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Text(settingsText(context,
                        zh: '图片格式暂不支持预览',
                        en: 'This image format cannot be previewed'))))),
        TextButton.icon(
            key: const ValueKey('favorite-image-fullscreen'),
            onPressed: _imageFullscreen,
            icon: const Icon(Icons.fullscreen),
            label:
                Text(settingsText(context, zh: '查看大图', en: 'View full image'))),
      ]);
    }
    if (_file != null && widget.asset.mimeType.startsWith('video/')) {
      return SizedBox(
          height: 320,
          child: ColoredBox(
              color: AppTokens.backgroundDark,
              child: _foreground
                  ? NativeMediaVideo(file: _file, autoPlay: false, muted: false)
                  : const Center(
                      child: Icon(Icons.pause_circle_outline,
                          color: AppTokens.textPrimaryDark))));
    }
    if (_file != null && _isAudio) {
      return FavoriteAudioPreview(
        key: ValueKey(_file!.path),
        file: _file!,
        title: widget.asset.fileName,
        fileSizeBytes: widget.asset.sizeBytes,
        durationHint: _audioDuration,
      );
    }
    return const SizedBox.shrink();
  }
}
