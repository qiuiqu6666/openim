import 'dart:io';

import 'package:flutter/material.dart';

import 'moments_secondary_layout.dart';

/// Composer attachments preserve the reference's single-image proportions.
/// Local file dimensions are presentation state and never affect publish IDs.
class MomentsComposerMediaGrid extends StatefulWidget {
  const MomentsComposerMediaGrid({
    super.key,
    required this.paths,
    required this.itemBuilder,
  });

  final List<String> paths;
  final Widget Function(BuildContext, int) itemBuilder;

  @override
  State<MomentsComposerMediaGrid> createState() =>
      _MomentsComposerMediaGridState();
}

class _MomentsComposerMediaGridState extends State<MomentsComposerMediaGrid> {
  double _ratio = 1.08;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant MomentsComposerMediaGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paths.length != widget.paths.length ||
        oldWidget.paths.firstOrNull != widget.paths.firstOrNull) {
      _ratio = 1.08;
      _resolve();
    }
  }

  void _resolve() {
    _stopListening();
    if (widget.paths.length != 1) return;
    final stream = FileImage(File(widget.paths.single))
        .resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, synchronous) {
      if (!mounted || info.image.width <= 0 || info.image.height <= 0) return;
      final ratio = (info.image.width / info.image.height).clamp(.75, 16 / 9);
      if (_ratio != ratio) setState(() => _ratio = ratio);
      _stopListening();
    }, onError: (Object _, StackTrace? __) => _stopListening());
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _stopListening() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.paths.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: widget.paths.length == 1 ? 1 : 3,
            childAspectRatio: widget.paths.length == 1 ? _ratio : 1,
            crossAxisSpacing: MomentsSecondaryLayout.gridGap,
            mainAxisSpacing: MomentsSecondaryLayout.gridGap),
        itemBuilder: widget.itemBuilder,
      );
}
