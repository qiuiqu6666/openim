import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

import 'sticker_bubble_layout.dart';

/// An image/GIF sticker whose message bounds follow the source aspect ratio.
/// The caller owns taps and the full-screen preview.
class ChatImageSticker extends StatefulWidget {
  const ChatImageSticker({
    super.key,
    required this.url,
    this.intrinsicSize,
    this.imageProvider,
  });

  final String url;
  final Size? intrinsicSize;
  final ImageProvider? imageProvider;

  @override
  State<ChatImageSticker> createState() => _ChatImageStickerState();
}

class _ChatImageStickerState extends State<ChatImageSticker> {
  static const _sizeCacheLimit = 128;
  static final _sizes = <String, Size>{};

  late ImageProvider _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _intrinsicSize;
  Size? _decodedSize;
  bool _failed = false;
  bool _probeStarted = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _updateSource();
  }

  void _updateSource() {
    _provider = widget.imageProvider ??
        ExtendedNetworkImageProvider(widget.url, cache: true);
    _decodedSize = null;
    _failed = false;
    _probeStarted = false;
    _intrinsicSize = _preferredSize();
  }

  Size? _preferredSize() {
    if (StickerBubbleLayout.isValidSize(widget.intrinsicSize)) {
      return widget.intrinsicSize;
    }
    if (_decodedSize != null) return _decodedSize;
    final cached = _sizes.remove(widget.url);
    if (cached != null) _sizes[widget.url] = cached;
    return cached;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _probeFirstFrame();
  }

  @override
  void didUpdateWidget(covariant ChatImageSticker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.imageProvider != widget.imageProvider) {
      _detachProbe();
      _generation++;
      _updateSource();
      _probeFirstFrame();
    } else if (oldWidget.intrinsicSize != widget.intrinsicSize) {
      _intrinsicSize = _preferredSize();
    }
  }

  void _probeFirstFrame() {
    if (_probeStarted) return;
    _probeStarted = true;
    final generation = _generation;
    final stream = _provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, synchronousCall) {
        final decoded =
            Size(info.image.width.toDouble(), info.image.height.toDouble());
        info.dispose();
        if (!mounted || generation != _generation) return;
        _detachProbe();
        if (!StickerBubbleLayout.isValidSize(decoded)) return;
        _sizes.remove(widget.url);
        _sizes[widget.url] = decoded;
        while (_sizes.length > _sizeCacheLimit) {
          _sizes.remove(_sizes.keys.first);
        }
        void update() {
          _decodedSize = decoded;
          _intrinsicSize = _preferredSize();
          _failed = false;
        }

        if (synchronousCall) {
          update();
        } else {
          setState(update);
        }
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted || generation != _generation) return;
        _detachProbe();
        setState(() => _failed = true);
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _detachProbe() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
    _stream = null;
  }

  @override
  void dispose() {
    _generation++;
    _detachProbe();
    super.dispose();
  }

  Widget _placeholder(BuildContext context, Size size) => ColoredBox(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
        child: Center(
          child: Icon(
            Icons.emoji_emotions_outlined,
            size: size.shortestSide * StickerBubbleLayout.placeholderIconFactor,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final source = _intrinsicSize;
          final screen = MediaQuery.sizeOf(context);
          final size = source == null
              ? StickerBubbleLayout.placeholderSize(
                  screenSize: screen,
                  isDesktop: StickerBubbleLayout.usesDesktopLimits,
                  availableWidth: constraints.maxWidth,
                  availableHeight: constraints.maxHeight)
              : StickerBubbleLayout.imageSize(source,
                  screenSize: screen,
                  isDesktop: StickerBubbleLayout.usesDesktopLimits,
                  availableWidth: constraints.maxWidth,
                  availableHeight: constraints.maxHeight);
          return ClipRRect(
            borderRadius: BorderRadius.circular(StickerBubbleLayout.radius),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: _failed
                  ? _placeholder(context, size)
                  : Image(
                      image: _provider,
                      width: size.width,
                      height: size.height,
                      fit: StickerBubbleLayout.imageFit(source, size),
                      frameBuilder: (context, child, frame, synchronous) =>
                          frame == null && !synchronous
                              ? _placeholder(context, size)
                              : child,
                      errorBuilder: (context, error, stackTrace) =>
                          _placeholder(context, size),
                    ),
            ),
          );
        },
      );
}
