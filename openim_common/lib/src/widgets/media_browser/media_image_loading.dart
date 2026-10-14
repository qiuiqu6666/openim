import 'dart:async';

import 'package:flutter/cupertino.dart';

/// Avoid a spinner flash for an image already in the decode/disk cache.
class MediaImageLoading extends StatefulWidget {
  const MediaImageLoading({super.key});

  @override
  State<MediaImageLoading> createState() => _MediaImageLoadingState();
}

class _MediaImageLoadingState extends State<MediaImageLoading> {
  Timer? _delay;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _delay = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _visible
      ? const Center(child: CupertinoActivityIndicator(radius: 15))
      : const SizedBox.expand();
}
