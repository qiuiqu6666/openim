import 'package:flutter/material.dart';

import '../../../services/moments_repository.dart';

/// A resource keeps its initial frame through download, decode and retry.
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
  late double _ratio = _initialRatio;

  double get _initialRatio {
    final width = widget.media.width ?? 0;
    final height = widget.media.height ?? 0;
    return width > 0 && height > 0 ? width / height : 1.08;
  }

  @override
  void didUpdateWidget(MomentsSingleMediaFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.mediaId != widget.media.mediaId ||
        oldWidget.media.contentPath != widget.media.contentPath ||
        oldWidget.media.thumbPath != widget.media.thumbPath) {
      _ratio = _initialRatio;
    }
  }

  void _dimensions(Size size) {
    // Decoded dimensions inform image decoding, never an already painted frame.
    // Unknown-size media is fully contained by MomentsMediaGrid instead.
  }

  @override
  Widget build(BuildContext context) {
    final ratio = _ratio;
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
