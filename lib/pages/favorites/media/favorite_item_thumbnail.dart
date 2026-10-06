import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/favorite_repository.dart';
import 'favorite_preview_loader.dart';

FavoriteAsset? favoriteThumbnailAsset(FavoriteItem item) {
  final images =
      item.assets.where((asset) => asset.mimeType.startsWith('image/'));
  final original =
      item.assets.where((asset) => asset.role == 'original').firstOrNull;
  final cover = item.coverAssetID ?? original?.coverAssetID;
  final explicit = images.where((asset) => asset.id == cover).firstOrNull;
  if (explicit != null) return explicit;
  final generated =
      images.where((asset) => asset.role != 'original').firstOrNull;
  if (generated != null) return generated;
  return item.kind == FavoriteKind.image ? images.firstOrNull : null;
}

/// List previews use authorized images/cover assets, never a video download or
/// an audio stream. Compact decoded pixels remain only while the row is alive.
class FavoriteItemThumbnail extends StatefulWidget {
  const FavoriteItemThumbnail(
      {super.key,
      required this.repository,
      required this.item,
      this.loaderFactory});
  final FavoriteRepository repository;
  final FavoriteItem item;
  final FavoritePreviewLoader Function()? loaderFactory;
  @override
  State<FavoriteItemThumbnail> createState() => _FavoriteItemThumbnailState();
}

class _FavoriteItemThumbnailState extends State<FavoriteItemThumbnail> {
  late final String _scope;
  FavoritePreviewLoader? _loader;
  Uint8List? _thumbnail;
  int? _duration;
  bool _loading = false, _invalid = false, _failed = false;
  bool get _current => !_invalid && widget.repository.isSessionCurrent(_scope);
  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
    widget.repository.addListener(_checkSession);
    unawaited(_load());
  }

  void _checkSession() {
    if (mounted && !_current && !_invalid) {
      _evict();
      setState(() {
        _invalid = true;
        _thumbnail = null;
      });
      unawaited(_loader?.close());
    }
  }

  void _evict() {
    if (_thumbnail != null) unawaited(MemoryImage(_thumbnail!).evict());
  }

  Future<void> _load() async {
    if (!widget.item.isReady || !_current) return;
    _loading = widget.item.kind != FavoriteKind.audio;
    try {
      var item = widget.item;
      if (item.assets.isEmpty ||
          (item.kind == FavoriteKind.video &&
              favoriteThumbnailAsset(item) == null)) {
        item = await widget.repository.getDetail(item.id);
      }
      if (!mounted || !_current || !item.isReady) return;
      if (item.kind == FavoriteKind.audio) {
        final duration = item.assets
            .where((asset) => asset.role == 'original')
            .firstOrNull
            ?.durationMs;
        if (mounted && _current) setState(() => _duration = duration);
        return;
      }
      final asset = favoriteThumbnailAsset(item);
      if (asset == null) return;
      final loader = widget.loaderFactory?.call() ?? FavoritePreviewLoader();
      _loader = loader;
      final file = await loader.load(widget.repository, item, asset, _scope);
      final raw = await file.readAsBytes();
      if (!mounted || !_current) return;
      final buffer = await ui.ImmutableBuffer.fromUint8List(raw);
      final codec = await ui.instantiateImageCodecWithSize(buffer,
          getTargetSize: (width, height) => width >= height
              ? ui.TargetImageSize(width: width > 160 ? 160 : width)
              : ui.TargetImageSize(height: height > 160 ? 160 : height));
      try {
        final frame = await codec.getNextFrame();
        try {
          final data =
              await frame.image.toByteData(format: ui.ImageByteFormat.png);
          if (mounted && _current && data != null) {
            setState(() => _thumbnail = data.buffer
                .asUint8List(data.offsetInBytes, data.lengthInBytes));
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      if (mounted && _current) setState(() => _failed = true);
    } finally {
      await _loader?.close();
      if (mounted && _current) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_checkSession);
    _evict();
    unawaited(_loader?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_invalid) return const SizedBox.shrink();
    if (widget.item.kind == FavoriteKind.audio) {
      final duration = _duration ??
          widget.item.assets
              .where((asset) => asset.role == 'original')
              .firstOrNull
              ?.durationMs;
      return Semantics(
          label: '语音预览',
          child: LayoutBuilder(builder: (context, constraints) {
            const icon =
                Icon(Icons.graphic_eq_rounded, color: AppTokens.accent);
            final time = duration == null
                ? null
                : Text('${(duration / 1000).ceil()}″',
                    maxLines: 1,
                    style: const TextStyle(
                        fontSize: AppTokens.captionFontSize,
                        color: AppTokens.accent));
            if (constraints.maxWidth <= AppTokens.s8 * 2) {
              return Center(
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        icon,
                        if (time != null) time,
                      ])));
            }
            return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
                child: Row(children: [
                  icon,
                  if (time != null) ...[
                    const SizedBox(width: AppTokens.s3),
                    Expanded(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: time)),
                  ],
                ]));
          }));
    }
    return Stack(fit: StackFit.expand, alignment: Alignment.center, children: [
      if (_thumbnail != null)
        Image.memory(_thumbnail!,
            fit: BoxFit.cover,
            key: ValueKey('favorite-thumbnail-${widget.item.id}'))
      else
        Center(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(AppTokens.s4),
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    _failed
                        ? Icons.broken_image_outlined
                        : widget.item.kind == FavoriteKind.video
                            ? Icons.videocam_outlined
                            : Icons.image_outlined,
                    color: AppTokens.accent)),
      if (widget.item.kind == FavoriteKind.video)
        Center(
            child: Icon(Icons.play_circle_fill,
                color: _thumbnail == null
                    ? AppTokens.accent
                    : AppTokens.onAccent)),
    ]);
  }
}
