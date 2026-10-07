import 'dart:math' as math;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/widgets.dart';

/// Shared full-screen sizing and gestures, independent of media ownership.
/// Tall images open at viewport width; other images remain fully visible.
class AdaptiveMediaImage extends StatefulWidget {
  const AdaptiveMediaImage({
    super.key,
    required this.image,
    this.loadStateChanged,
    this.enableSlideOutPage = true,
    this.clearMemoryCacheWhenDispose = false,
  });

  final ImageProvider image;
  final LoadStateChanged? loadStateChanged;
  final bool enableSlideOutPage;
  final bool clearMemoryCacheWhenDispose;

  @override
  State<AdaptiveMediaImage> createState() => _AdaptiveMediaImageState();
}

class _AdaptiveMediaImageState extends State<AdaptiveMediaImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _zoomController;
  Animation<double>? _zoom;
  ExtendedImageGestureState? _zoomTarget;
  Offset? _zoomPosition;

  @override
  void initState() {
    super.initState();
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(_animateZoom);
  }

  void _animateZoom() {
    final target = _zoomTarget;
    if (target?.mounted != true || _zoom == null) return;
    target!
        .handleDoubleTap(scale: _zoom!.value, doubleTapPosition: _zoomPosition);
  }

  @override
  void didUpdateWidget(covariant AdaptiveMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      _zoomController.stop();
      _zoomTarget = null;
    }
  }

  @override
  void dispose() {
    _zoomController.dispose();
    super.dispose();
  }

  GestureConfig _gestureConfig(ExtendedImageState state, Size viewport) {
    final image = state.extendedImageInfo?.image;
    var initialScale = 1.0;
    if (image != null &&
        image.width > 0 &&
        image.height / image.width >= 2.2 &&
        viewport.isFinite &&
        !viewport.isEmpty) {
      // ExtendedImage scales relative to BoxFit.contain. Do not cap this at
      // the ordinary 3x zoom limit: very long screenshots can need much more.
      initialScale = math.max(
          1.0, viewport.width * image.height / (viewport.height * image.width));
    }
    return GestureConfig(
      minScale: 0.9,
      animationMinScale: 0.7,
      initialScale: initialScale,
      maxScale: initialScale * 3,
      animationMaxScale: initialScale * 3.5,
      inPageView: true,
      initialAlignment: initialScale > 1
          ? InitialAlignment.topCenter
          : InitialAlignment.center,
    );
  }

  void _doubleTap(ExtendedImageGestureState state, Size viewport) {
    final base =
        _gestureConfig(state.widget.extendedImageState, viewport).initialScale;
    final begin = state.gestureDetails?.totalScale ?? base;
    final end = begin <= base * 1.01 ? base * 2 : base;
    _zoomController.stop();
    _zoomTarget = state;
    _zoomPosition = state.pointerDownPosition;
    _zoom = Tween<double>(begin: begin, end: end).animate(_zoomController);
    if (MediaQuery.disableAnimationsOf(context)) {
      state.handleDoubleTap(scale: end, doubleTapPosition: _zoomPosition);
    } else {
      _zoomController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          return ExtendedImage(
            image: widget.image,
            fit: BoxFit.contain,
            mode: ExtendedImageMode.gesture,
            enableSlideOutPage: widget.enableSlideOutPage,
            clearMemoryCacheWhenDispose: widget.clearMemoryCacheWhenDispose,
            enableLoadState: widget.loadStateChanged != null,
            handleLoadingProgress: true,
            loadStateChanged: widget.loadStateChanged,
            initGestureConfigHandler: (state) =>
                _gestureConfig(state, viewport),
            onDoubleTap: (state) => _doubleTap(state, viewport),
          );
        },
      );
}
