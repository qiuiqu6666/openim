import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../moments_text.dart';

/// Keeps its navigation slot while the visual enters and exits.
class MomentsHeaderLoading extends StatefulWidget {
  const MomentsHeaderLoading({super.key, required this.loading});

  final bool loading;
  static const size = 24.0;
  static const revolution = Duration(milliseconds: 1200);
  static const entryDuration = Duration(milliseconds: 360);
  static const minimumSpin = Duration(milliseconds: 600);
  static const exitDuration = Duration(milliseconds: 260);

  @override
  State<MomentsHeaderLoading> createState() => _MomentsHeaderLoadingState();
}

class _MomentsHeaderLoadingState extends State<MomentsHeaderLoading>
    with TickerProviderStateMixin {
  late final _position = AnimationController(
      vsync: this,
      duration: MomentsHeaderLoading.entryDuration,
      reverseDuration: MomentsHeaderLoading.exitDuration)
    ..addStatusListener(_positionChanged);
  late final _rotation = AnimationController(
      vsync: this, duration: MomentsHeaderLoading.revolution);
  late final _hold = AnimationController(
      vsync: this, duration: MomentsHeaderLoading.minimumSpin)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && !widget.loading) {
        _syncPosition();
      }
    });
  bool _reduced = false;
  bool _enabled = true;

  void _positionChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_reduced) {
      _hold.forward(from: 0);
    }
    _syncRotation();
    if (mounted) setState(() {});
  }

  void _syncRotation() {
    final rotate =
        !_reduced && _enabled && _position.status == AnimationStatus.completed;
    if (rotate && !_rotation.isAnimating) {
      _rotation.repeat();
    } else if (!rotate) {
      _rotation.stop();
    }
  }

  void _syncPosition() {
    if (_reduced) {
      _hold.stop();
      _position.value = widget.loading ? 1 : 0;
    } else if (widget.loading) {
      _position.forward();
    } else if (_position.isCompleted && _hold.isCompleted) {
      _position.reverse();
    }
    // A quick response does not interrupt entry or its minimum spin.
    // Only the visual waits; the page consumes the result immediately.
    if (!_reduced &&
        _position.isCompleted &&
        !_hold.isAnimating &&
        !_hold.isCompleted) {
      _hold.forward();
    }
    _syncRotation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _enabled = TickerMode.valuesOf(context).enabled;
    _syncPosition();
  }

  @override
  void didUpdateWidget(MomentsHeaderLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading) _syncPosition();
  }

  @override
  void dispose() {
    _hold.dispose();
    _position.dispose();
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: MomentsHeaderLoading.size,
        child: AnimatedBuilder(
          animation: _position,
          builder: (context, child) {
            if (!widget.loading && _position.isDismissed) {
              return const SizedBox.shrink();
            }
            final travel = MediaQuery.viewPaddingOf(context).top +
                MediaQuery.paddingOf(context).top +
                kMinInteractiveDimension +
                MomentsHeaderLoading.size;
            return Transform.translate(
              key: const ValueKey('moments_header_loading_motion'),
              offset: Offset(
                  0,
                  -travel *
                      (1 - Curves.easeOutCubic.transform(_position.value))),
              child: child,
            );
          },
          child: Semantics(
            label: momentsText(context, zh: '正在加载', en: 'Loading'),
            liveRegion: true,
            child: IgnorePointer(
              child: RepaintBoundary(
                key: const ValueKey('moments_header_loading'),
                child: RotationTransition(
                  turns: _rotation,
                  child: SvgPicture.asset(
                    'assets/images/moments_loading_aperture.svg',
                    width: MomentsHeaderLoading.size,
                    height: MomentsHeaderLoading.size,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
