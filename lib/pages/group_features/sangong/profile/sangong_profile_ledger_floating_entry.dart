// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../services/agent_rebate_float_prefs.dart';
import '../support/sangong_ui.dart' show AppI18n;
import '../utils/group_game_float_geometry.dart';
import 'sangong_profile_ledger_tokens.dart';

/// The profile's circular ledger entry, positioned inside its owning Stack.
///
/// [preferenceKey] must identify the viewing account. This ledger namespace is
/// separate from the group agent float. Narrow panes never overwrite the saved
/// full-screen position. A null callback keeps the entry visible but disabled.
class SangongProfileLedgerFloatingEntry extends StatefulWidget {
  const SangongProfileLedgerFloatingEntry({
    super.key,
    required this.preferenceKey,
    this.onOpenLedger,
  });

  final String preferenceKey;
  final VoidCallback? onOpenLedger;

  @override
  State<SangongProfileLedgerFloatingEntry> createState() =>
      _SangongProfileLedgerFloatingEntryState();
}

class _SangongProfileLedgerFloatingEntryState
    extends State<SangongProfileLedgerFloatingEntry> {
  Offset? _offset;
  Offset? _restoredOffset;
  bool _dragging = false;
  bool _prefsLoaded = false;
  int _restoreGeneration = 0;

  String get _storageKey => 'sangong_profile_ledger:${widget.preferenceKey}';

  @override
  void initState() {
    super.initState();
    unawaited(_restorePrefs());
  }

  @override
  void didUpdateWidget(SangongProfileLedgerFloatingEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferenceKey == widget.preferenceKey) return;
    _offset = null;
    _restoredOffset = null;
    _dragging = false;
    _prefsLoaded = false;
    unawaited(_restorePrefs());
  }

  Future<void> _restorePrefs() async {
    final generation = ++_restoreGeneration;
    final storageKey = _storageKey;
    Offset? saved;
    try {
      saved = await AgentRebateFloatPrefs.instance.readOffset(storageKey);
    } catch (_) {
      // A position preference failure must not block a permitted ledger read.
    }
    if (!mounted ||
        generation != _restoreGeneration ||
        storageKey != _storageKey) {
      return;
    }
    setState(() {
      _restoredOffset = saved;
      _prefsLoaded = true;
    });
  }

  Size _paneSizeOf(BuildContext context, BoxConstraints constraints) {
    final biggest = constraints.biggest;
    if (biggest.width.isFinite &&
        biggest.height.isFinite &&
        biggest.width > 0 &&
        biggest.height > 0) {
      return biggest;
    }
    return MediaQuery.sizeOf(context);
  }

  bool _isNearlyFullScreen(Size paneSize, Size windowSize) =>
      (paneSize.width - windowSize.width).abs() <
          SangongProfileLedgerTokens.fullScreenWidthTolerance &&
      (paneSize.height - windowSize.height).abs() <
          SangongProfileLedgerTokens.fullScreenHeightTolerance;

  EdgeInsets _panePaddingOf(BuildContext context, Size paneSize) {
    final media = MediaQuery.of(context);
    return _isNearlyFullScreen(paneSize, media.size)
        ? media.viewPadding
        : EdgeInsets.zero;
  }

  Offset _clamp(Offset offset, Size paneSize, EdgeInsets padding) =>
      clampGroupGameFloatOffset(
        offset: offset,
        screenSize: paneSize,
        childSize: SangongProfileLedgerTokens.size,
        viewPadding: padding,
      );

  Offset _resolvedOffset(Size paneSize, EdgeInsets padding) {
    final restored = _restoredOffset;
    if (!_dragging && restored != null) {
      _restoredOffset = null;
      final clamped = _clamp(restored, paneSize, padding);
      if ((restored.dx - clamped.dx).abs() <
              SangongProfileLedgerTokens.restoreTolerance &&
          (restored.dy - clamped.dy).abs() <
              SangongProfileLedgerTokens.restoreTolerance) {
        _offset = restored;
      }
    }
    final base = _offset ??
        defaultGroupGameFloatOffset(
          screenSize: paneSize,
          childSize: SangongProfileLedgerTokens.size,
          bottomInset: padding.bottom,
        );
    return _offset = _clamp(base, paneSize, padding);
  }

  void _startDrag(DragStartDetails details) {
    if (!_prefsLoaded) return;
    setState(() {
      _restoredOffset = null;
      _dragging = true;
    });
  }

  void _updateDrag(
      DragUpdateDetails details, Size paneSize, EdgeInsets padding) {
    if (!_dragging) return;
    setState(() {
      _offset = _clamp(_resolvedOffset(paneSize, padding) + details.delta,
          paneSize, padding);
    });
  }

  void _finishDrag(Size paneSize, EdgeInsets padding) {
    if (!_dragging || _offset == null) return;
    final snapped = snapGroupGameFloatOffsetToHorizontalEdge(
      offset: _offset!,
      screenSize: paneSize,
      childSize: SangongProfileLedgerTokens.size,
      viewPadding: padding,
    );
    setState(() {
      _dragging = false;
      _offset = snapped;
    });
    if (_isNearlyFullScreen(paneSize, MediaQuery.sizeOf(context))) {
      unawaited(_persistOffset(_storageKey, snapped));
    }
  }

  Future<void> _persistOffset(String storageKey, Offset offset) async {
    try {
      await AgentRebateFloatPrefs.instance.writeOffset(storageKey, offset);
    } catch (_) {
      // Dragging remains available if the optional local preference cannot save.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        elevation: SangongProfileLedgerTokens.overlayElevation,
        child: LayoutBuilder(builder: (context, constraints) {
          final paneSize = _paneSizeOf(context, constraints);
          final padding = _panePaddingOf(context, paneSize);
          final offset = _resolvedOffset(paneSize, padding);
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final i18n = AppI18n.of(context);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedPositioned(
                duration: _dragging
                    ? Duration.zero
                    : SangongProfileLedgerTokens.snapDuration,
                curve: SangongProfileLedgerTokens.snapCurve,
                left: offset.dx,
                top: offset.dy,
                child: GestureDetector(
                  behavior: HitTestBehavior.deferToChild,
                  onPanStart: _startDrag,
                  onPanUpdate: (details) =>
                      _updateDrag(details, paneSize, padding),
                  onPanEnd: (_) => _finishDrag(paneSize, padding),
                  onPanCancel: () => _finishDrag(paneSize, padding),
                  child: Tooltip(
                    message: i18n.t(zhHans: '流水', zhHant: '流水', en: 'Ledger'),
                    child: Material(
                      color: SangongProfileLedgerTokens.surface(dark: isDark),
                      shape: const CircleBorder(),
                      elevation: _dragging
                          ? SangongProfileLedgerTokens.dragElevation
                          : SangongProfileLedgerTokens.elevation,
                      shadowColor:
                          SangongProfileLedgerTokens.shadow(dark: isDark),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _dragging || !_prefsLoaded
                            ? null
                            : widget.onOpenLedger,
                        child: SizedBox.fromSize(
                          size: SangongProfileLedgerTokens.size,
                          child: Center(
                            child: Text(
                              i18n.t(zhHans: '流', zhHant: '流', en: 'L'),
                              style: const TextStyle(
                                fontSize: SangongProfileLedgerTokens.fontSize,
                                color: SangongProfileLedgerTokens.accent,
                                fontWeight:
                                    SangongProfileLedgerTokens.fontWeight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
