import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Live backdrop for media overlays. Navigation surfaces intentionally use an
/// opaque tint, so they must not be reused over pictures or video textures.
class MediaPreviewGlass extends StatefulWidget {
  const MediaPreviewGlass({
    super.key,
    required this.borderRadius,
    required this.child,
    this.interactive = false,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final bool interactive;

  @override
  State<MediaPreviewGlass> createState() => _MediaPreviewGlassState();
}

class _MediaPreviewGlassState extends State<MediaPreviewGlass> {
  final Set<int> _pointers = {};

  void _press(int pointer, bool down) {
    if (!widget.interactive) return;
    setState(() {
      if (down) {
        _pointers.add(pointer);
      } else {
        _pointers.remove(pointer);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    return Listener(
      onPointerDown: (event) => _press(event.pointer, true),
      onPointerUp: (event) => _press(event.pointer, false),
      onPointerCancel: (event) => _press(event.pointer, false),
      child: AnimatedScale(
        scale: _pointers.isNotEmpty && !MediaQuery.disableAnimationsOf(context)
            ? .96
            : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: BackdropFilter(
            // Sample the live scene behind each clipped control. No screenshot
            // cache: paging, zooming and video frames update the same backdrop.
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: ColoredBox(
              // Darken bright media for white foregrounds, then add a faint
              // highlight that remains visible even over a black letterbox.
              color: Colors.black.withValues(alpha: highContrast ? .78 : .64),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: .12),
                      Colors.white.withValues(alpha: .06),
                    ],
                  ),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
