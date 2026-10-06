import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../../services/moments_repository.dart';
import '../presentation/moments_text.dart';
import '../presentation/moments_theme.dart';

class MomentsMediaImage extends StatefulWidget {
  const MomentsMediaImage({
    super.key,
    required this.repository,
    required this.media,
    this.thumbnail = true,
    this.fit = BoxFit.cover,
    this.onDimensions,
  });

  final MomentsRepository repository;
  final MomentMedia media;
  final bool thumbnail;
  final BoxFit fit;
  final ValueChanged<Size>? onDimensions;

  @override
  State<MomentsMediaImage> createState() => _MomentsMediaImageState();
}

class _MomentsMediaImageState extends State<MomentsMediaImage> {
  late Future<_ProtectedImage> _bytes;
  late String _authorizationScope;
  late String _session;
  ImageProvider? _image;
  int _generation = 0;
  bool _revoked = false;
  Size? _reportedSize;

  @override
  void initState() {
    super.initState();
    _session = widget.repository.sessionScope;
    widget.repository.addListener(_permissionChanged);
    _load();
  }

  @override
  void didUpdateWidget(MomentsMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.mediaId != widget.media.mediaId ||
        oldWidget.media.contentPath != widget.media.contentPath ||
        oldWidget.media.thumbPath != widget.media.thumbPath ||
        oldWidget.repository != widget.repository ||
        oldWidget.thumbnail != widget.thumbnail) {
      if (oldWidget.repository != widget.repository) {
        oldWidget.repository.removeListener(_permissionChanged);
        widget.repository.addListener(_permissionChanged);
        _session = widget.repository.sessionScope;
      }
      _load();
    }
  }

  void _evict() {
    if (_image != null) unawaited(_image!.evict());
    _image = null;
  }

  void _load() {
    _evict();
    _revoked = false;
    _generation++;
    _reportedSize = null;
    _authorizationScope = widget.repository.authorizationScope;
    _bytes = _prepareImage(widget.repository
        .downloadMedia(widget.media, thumbnail: widget.thumbnail));
    // Permission/token failure can complete before the next frame installs a
    // FutureBuilder listener; retain the failed result without a global error.
    _bytes.ignore();
  }

  // Read encoded dimensions without rasterizing a phone photo at source size.
  // The original ratio remains available to the single-photo layout even when
  // its displayed bitmap is decoded at a much smaller size.
  Future<_ProtectedImage> _prepareImage(Future<Uint8List> download) async {
    final bytes = await download;
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return _ProtectedImage(bytes,
          Size(descriptor.width.toDouble(), descriptor.height.toDouble()));
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  void _reportDimensions(Size size) {
    if (widget.onDimensions == null || _reportedSize == size) return;
    _reportedSize = size;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_revoked &&
          generation == _generation &&
          _authorizationScope == widget.repository.authorizationScope &&
          widget.repository.isSessionCurrent(_session)) {
        widget.onDimensions?.call(size);
      }
    });
  }

  ImageProvider _provider(
      _ProtectedImage image, BoxConstraints constraints, double pixelRatio) {
    final size = image.size;
    final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 240.0;
    final height =
        constraints.maxHeight.isFinite ? constraints.maxHeight : width;
    final scaleForBox = widget.fit == BoxFit.contain
        ? math.min(width / size.width, height / size.height)
        : math.max(width / size.width, height / size.height);
    final scale = math.min(
        1.0,
        math.min(scaleForBox * pixelRatio,
            1080 / math.max(size.width, size.height)));
    final base = MemoryImage(image.bytes);
    final ImageProvider provider = scale >= 1
        ? base
        : ResizeImage(base,
            width: math.max(1, (size.width * scale).ceil()),
            height: math.max(1, (size.height * scale).ceil()));
    if (_image != provider) {
      _evict();
      _image = provider;
    }
    return provider;
  }

  void _permissionChanged() {
    if (_authorizationScope == widget.repository.authorizationScope) return;
    if (!mounted) return;
    setState(() {
      _evict();
      _generation++;
      _authorizationScope = widget.repository.authorizationScope;
      _revoked = true;
      _bytes = Future.error(
          const MomentsException('查看权限已变更', permissionDenied: true));
      _bytes.ignore();
    });
  }

  @override
  void dispose() {
    widget.repository.removeListener(_permissionChanged);
    _evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_ProtectedImage>(
        key: ValueKey(_generation),
        future: _bytes,
        builder: (context, snapshot) {
          final dark = momentsDark(context);
          if (snapshot.hasData &&
              !_revoked &&
              widget.repository.isSessionCurrent(_session) &&
              _authorizationScope == widget.repository.authorizationScope) {
            final image = snapshot.data!;
            _reportDimensions(image.size);
            return LayoutBuilder(
                builder: (context, constraints) => Image(
                    image: _provider(image, constraints,
                        MediaQuery.devicePixelRatioOf(context)),
                    fit: widget.fit,
                    gaplessPlayback: false,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, __, ___) => Icon(
                        Icons.broken_image_outlined,
                        color: AppTokens.textSecondary(dark: dark))));
          }
          return ColoredBox(
            color: MomentsTheme.panel(dark),
            child: Center(
              child: snapshot.hasError || _revoked
                  ? IconButton(
                      tooltip:
                          momentsText(context, zh: '重试图片', en: 'Retry image'),
                      onPressed: widget.repository.isSessionCurrent(_session)
                          ? () => setState(_load)
                          : null,
                      icon: Icon(Icons.image_not_supported_outlined,
                          color: AppTokens.textSecondary(dark: dark)))
                  : const SizedBox.square(
                      dimension: AppTokens.s7,
                      child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        },
      );
}

class _ProtectedImage {
  const _ProtectedImage(this.bytes, this.size);
  final Uint8List bytes;
  final Size size;
}
