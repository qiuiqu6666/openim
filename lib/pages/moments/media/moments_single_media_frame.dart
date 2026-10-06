import 'package:flutter/material.dart';

import '../../../services/moments_repository.dart';

/// Metadata or decoded image dimensions drive the same ratios as 99chat.
class MomentsSingleMediaFrame extends StatefulWidget {
  const MomentsSingleMediaFrame({
    super.key,
    required this.media,
    required this.imageBuilder,
    this.maxLongImageHeight = 420,
  });

  final MomentMedia media;
  final Widget Function(ValueChanged<Size> onDimensions) imageBuilder;
  final double maxLongImageHeight;

  @override
  State<MomentsSingleMediaFrame> createState() =>
      _MomentsSingleMediaFrameState();
}

class _MomentsSingleMediaFrameState extends State<MomentsSingleMediaFrame> {
  Size? _decodedSize;

  @override
  void didUpdateWidget(MomentsSingleMediaFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.mediaId != widget.media.mediaId ||
        oldWidget.media.contentPath != widget.media.contentPath ||
        oldWidget.media.thumbPath != widget.media.thumbPath) {
      _decodedSize = null;
    }
  }

  void _dimensions(Size size) {
    if (!mounted ||
        size.width <= 0 ||
        size.height <= 0 ||
        size == _decodedSize) {
      return;
    }
    setState(() => _decodedSize = size);
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.media.width ?? 0;
    final height = widget.media.height ?? 0;
    final ratio = width > 0 && height > 0
        ? width / height
        : _decodedSize == null
            ? 1.08
            : _decodedSize!.width / _decodedSize!.height;
    final child = widget.imageBuilder(_dimensions);
    return LayoutBuilder(builder: (context, constraints) {
      if (ratio < .75 && constraints.maxWidth.isFinite) {
        final imageHeight = (constraints.maxWidth / ratio)
            .clamp(0.0, widget.maxLongImageHeight);
        return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
                width: imageHeight * ratio, height: imageHeight, child: child));
      }
      return AspectRatio(aspectRatio: ratio.clamp(.75, 16 / 9), child: child);
    });
  }
}
