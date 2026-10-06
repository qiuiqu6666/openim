import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../widgets/live_style.dart';
import 'live_cast_service.dart';

/// Matches 99chat: Android system cast settings or the native AirPlay picker.
class LiveCastButton extends StatefulWidget {
  const LiveCastButton({
    super.key,
    this.foregroundColor,
    this.onError,
    this.service = const LiveCastService(),
    this.platform,
  });

  final Color? foregroundColor;
  final ValueChanged<String>? onError;
  final LiveCastService service;
  final TargetPlatform? platform;

  @override
  State<LiveCastButton> createState() => _LiveCastButtonState();
}

class _LiveCastButtonState extends State<LiveCastButton> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.service.openSystemPicker(platform: widget.platform);
    } on LiveCastFailure catch (error) {
      if (mounted) (widget.onError ?? IMViews.showToast)(error.message);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = widget.platform ?? defaultTargetPlatform;
    if (kIsWeb ||
        (platform != TargetPlatform.android &&
            platform != TargetPlatform.iOS)) {
      return const SizedBox.shrink();
    }
    final foreground = widget.foregroundColor ?? LiveStyle.screenInk;
    if (platform == TargetPlatform.iOS) {
      return Tooltip(
        message: '投屏',
        child: SizedBox.square(
          dimension: LiveStyle.controlExtent,
          child: UiKitView(
            key: ValueKey(foreground.toARGB32()),
            viewType: 'openim_group_live_airplay_picker',
            layoutDirection: Directionality.of(context),
            creationParams: <String, dynamic>{
              'tint': foreground.toARGB32(),
              'activeTint': AppTokens.accent.toARGB32(),
            },
            creationParamsCodec: const StandardMessageCodec(),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: _opening ? '正在打开投屏设置' : '投屏',
      constraints: const BoxConstraints.tightFor(
        width: LiveStyle.controlExtent,
        height: LiveStyle.controlExtent,
      ),
      color: foreground,
      disabledColor: foreground.withValues(alpha: .5),
      iconSize: LiveStyle.controlIconSize,
      onPressed: _opening ? null : () => unawaited(_open()),
      icon: const Icon(Icons.cast_rounded),
    );
  }
}
