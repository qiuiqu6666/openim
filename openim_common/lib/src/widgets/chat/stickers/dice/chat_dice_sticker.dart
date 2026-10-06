import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:focus_detector_v2/focus_detector_v2.dart';

import '../../../../res/app_tokens.dart';
import '../../../../res/strings.dart';
import '../sticker_bubble_layout.dart';
import 'dice_sticker_layout.dart';
import 'dice_webp_frames.dart';
import 'dice_webp_playback.dart';

/// A fixed dice outcome. Animation never chooses or changes the sent value.
class ChatDiceSticker extends StatefulWidget {
  const ChatDiceSticker({
    super.key,
    required this.value,
    this.messageId,
    this.sentAt,
    this.animate = true,
    this.size,
    this.tightPreview = false,
  });

  final int value;
  final String? messageId;
  final int? sentAt;
  final bool animate;
  final double? size;

  /// Fit the settled dice itself into a panel tile rather than its empty stage.
  final bool tightPreview;

  static const animationWindow = Duration(minutes: 1);
  static String assetFor(int value) => 'assets/chat/dice/dice_$value.webp';

  @override
  State<ChatDiceSticker> createState() => _ChatDiceStickerState();
}

class _ChatDiceStickerState extends State<ChatDiceSticker>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // A rebuilt/recycled SDK message or resend must not roll a second time.
  // The short age window also keeps evicted entries and older history static.
  static const _playedLimit = 1024;
  static final _played = <String>{};

  late final Ticker _ticker;
  Duration? _lastTick;
  AssetBundle? _bundle;
  DiceWebpPlayback? _playback;
  ui.Image? _stillImage;
  bool _failed = false;
  bool _visible = false;
  bool _foreground = true;
  bool _routeActive = true;
  bool _tickersEnabled = true;
  bool _reduceMotion = false;
  bool _completed = false;
  int _generation = 0;

  bool get _valid => widget.value >= 1 && widget.value <= 6;
  bool get _canPlay =>
      _visible && _foreground && _routeActive && _tickersEnabled;

  bool get _recent {
    final time = widget.sentAt;
    if (time == null || time <= 0 || widget.messageId?.isNotEmpty != true) {
      return false;
    }
    final age = DateTime.now().millisecondsSinceEpoch - time;
    return age >= -ChatDiceSticker.animationWindow.inMilliseconds &&
        age <= ChatDiceSticker.animationWindow.inMilliseconds;
  }

  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    _reset();
  }

  void _reset() {
    _generation++;
    _stopTicker();
    _disconnectPlayback();
    _retireImage(_stillImage);
    _stillImage = null;
    _failed = false;
    final bundle = _bundle;
    final resumable = bundle != null &&
        DiceWebpPlayback.hasInProgress(bundle, _asset, widget.messageId ?? '');
    _completed = !widget.animate ||
        !_recent ||
        _reduceMotion ||
        (_played.contains(widget.messageId) && !resumable);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = ModalRoute.isCurrentOf(context) ?? true;
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final bundle = DefaultAssetBundle.of(context);
    if (!identical(bundle, _bundle)) {
      _bundle = bundle;
      _reset();
      unawaited(_load());
    }
    _drive();
  }

  @override
  void didUpdateWidget(covariant ChatDiceSticker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.messageId != widget.messageId) {
      _reset();
      unawaited(_load());
    }
    _drive();
  }

  void _remember() {
    final id = widget.messageId;
    if (id == null || id.isEmpty) return;
    _played.remove(id);
    _played.add(id);
    while (_played.length > _playedLimit) {
      _played.remove(_played.first);
    }
  }

  void _finish() {
    _remember();
    _generation++;
    _stopTicker();
    _disconnectPlayback();
    setState(() => _completed = true);
    unawaited(_load());
  }

  String get _asset =>
      'packages/openim_common/${ChatDiceSticker.assetFor(widget.value)}';

  Future<void> _load() async {
    final bundle = _bundle;
    if (!_valid || bundle == null) return;
    final generation = _generation;
    final asset = _asset;
    try {
      if (_completed || _reduceMotion) {
        final image = await DiceWebpFrames.loadFinal(bundle, asset);
        if (!mounted || generation != _generation) {
          image.dispose();
          return;
        }
        final previous = _stillImage;
        setState(() => _stillImage = image);
        _retireImage(previous);
        return;
      }
      _playback = DiceWebpPlayback.acquire(bundle, asset, widget.messageId!)
        ..addListener(_playbackChanged);
      _playbackChanged();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _stopTicker();
      setState(() => _failed = true);
    }
  }

  void _onTick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    _playback?.advance(previous == null ? Duration.zero : elapsed - previous);
  }

  void _stopTicker() {
    _ticker.stop();
    _lastTick = null;
  }

  void _playbackChanged() {
    if (!mounted) return;
    final playback = _playback;
    if (playback == null) return;
    if (playback.completed) {
      _completed = true;
      _remember();
    }
    setState(() => _failed = playback.failed);
    _drive();
  }

  void _disconnectPlayback() {
    final playback = _playback;
    _playback = null;
    playback?.removeListener(_playbackChanged);
    playback?.release();
  }

  void _retireImage(ui.Image? image) {
    if (image == null) return;
    // RawImage may still paint its previous handle before the next rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  void _drive() {
    if (!_valid || _completed || _failed) {
      _stopTicker();
      return;
    }
    if (!widget.animate || _reduceMotion) {
      _finish();
      return;
    }
    if (_playback?.image == null || !_canPlay) {
      _stopTicker();
      return;
    }
    if (!_ticker.isActive) {
      _remember();
      _ticker.start();
    }
  }

  void _setVisible(bool visible) {
    if (!mounted || visible == _visible) return;
    _visible = visible;
    _drive();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _drive();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _disconnectPlayback();
    _retireImage(_stillImage);
    _stillImage = null;
    _ticker.dispose();
    super.dispose();
  }

  Widget _fallback(BuildContext context) => Center(
        child: Text('[${StrRes.diceLabel}]',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTokens.textSecondary(
                    dark: Theme.of(context).brightness == Brightness.dark))),
      );

  Widget _imageView(Size canvas) {
    final crop = widget.tightPreview && _completed
        ? DiceStickerLayout.previewViewport
        : null;
    final imageSize = crop == null ? canvas : DiceStickerLayout.sourceSize;
    final image = RawImage(
      key: ValueKey((widget.messageId, widget.value)),
      image: _playback?.image ?? _stillImage,
      width: imageSize.width,
      height: imageSize.height,
      fit: BoxFit.contain,
    );
    if (crop == null) return image;
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: crop.width,
        height: crop.height,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: imageSize.width,
            maxWidth: imageSize.width,
            minHeight: imageSize.height,
            maxHeight: imageSize.height,
            child: Transform.translate(
              offset: Offset(-crop.left, -crop.top),
              child: image,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final preferred = widget.size;
          final size = preferred != null && preferred.isFinite && preferred > 0
              ? constraints.constrain(Size.square(preferred))
              : StickerBubbleLayout.imageSize(
                  DiceStickerLayout.sourceSize,
                  screenSize: MediaQuery.sizeOf(context),
                  isDesktop: StickerBubbleLayout.usesDesktopLimits,
                  availableWidth: constraints.maxWidth,
                  availableHeight: constraints.maxHeight,
                );
          final content = SizedBox(
            width: size.width,
            height: size.height,
            child: Semantics(
              image: true,
              label: _valid
                  ? '${StrRes.diceLabel} ${StrRes.dicePoint(widget.value)}'
                  : StrRes.diceLabel,
              child: ExcludeSemantics(
                child:
                    _valid && !_failed ? _imageView(size) : _fallback(context),
              ),
            ),
          );
          // Static thumbnails and history need no visibility observer/timer.
          if (_completed || !_valid || _failed) return content;
          return FocusDetector(
            onVisibilityGained: () => _setVisible(true),
            onVisibilityLost: () => _setVisible(false),
            child: content,
          );
        },
      );
}
