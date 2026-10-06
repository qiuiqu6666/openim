import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Resolves a local thumbnail once per path without blocking message builds.
class ChatVideoThumbnail extends StatefulWidget {
  const ChatVideoThumbnail(
      {super.key,
      required this.path,
      required this.url,
      required this.width,
      this.fallbackBuilder,
      this.imageBuilder});
  final String? path;
  final String? url;
  final double width;
  final WidgetBuilder? fallbackBuilder;
  final Widget Function(BuildContext context, Widget image)? imageBuilder;

  @override
  State<ChatVideoThumbnail> createState() => ChatVideoThumbnailState();
}

class ChatVideoThumbnailState extends State<ChatVideoThumbnail> {
  File? _file;
  bool _pathResolved = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _resolvePath();
  }

  @override
  void didUpdateWidget(covariant ChatVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _file = null;
      _pathResolved = false;
      _resolvePath();
    }
  }

  Future<void> _resolvePath() async {
    final generation = ++_generation;
    final path = widget.path;
    if (path == null || path.isEmpty) {
      _pathResolved = true;
      return;
    }
    try {
      final file = File(path);
      final exists = await file.exists();
      if (mounted && generation == _generation) {
        setState(() {
          _file = exists ? file : null;
          _pathResolved = true;
        });
      }
    } catch (_) {
      // A missing or inaccessible local file can still use the remote snapshot.
      if (mounted && generation == _generation) {
        setState(() => _pathResolved = true);
      }
    }
  }

  Widget _fallback(BuildContext context) =>
      widget.fallbackBuilder?.call(context) ??
      ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHigh);

  Widget _frame(
      BuildContext context, Widget image, int? frame, bool synchronous) {
    if (frame == null && !synchronous) return _fallback(context);
    return widget.imageBuilder!(context, image);
  }

  Widget _remote(BuildContext context, int? cacheWidth) {
    final url = widget.url;
    return url != null && url.isNotEmpty
        ? Image.network(OpenIMMediaUrl.resolve(url, imApiUrl: Config.imApiUrl),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            frameBuilder: widget.imageBuilder == null ? null : _frame,
            errorBuilder: (_, __, ___) => _fallback(context))
        : _fallback(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!_pathResolved) return _fallback(context);
    final cacheWidth = ImageUtil.decodeDimension(
        widget.width, MediaQuery.devicePixelRatioOf(context));
    final file = _file;
    return file == null
        ? _remote(context, cacheWidth)
        : Image.file(file,
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            frameBuilder: widget.imageBuilder == null ? null : _frame,
            errorBuilder: (_, __, ___) => _remote(context, cacheWidth));
  }
}
