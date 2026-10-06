import 'package:flutter/material.dart';

import '../casting/live_cast_button.dart';
import 'live_style.dart';
import 'live_watching_bottom_bar.dart';

/// Stable waiting/error presentation shared by inline and fullscreen watching.
class LiveWaitingView extends StatelessWidget {
  const LiveWaitingView({
    super.key,
    required this.loading,
    required this.active,
    required this.message,
    required this.muted,
    required this.onClose,
    required this.onFullscreen,
    required this.onMute,
    required this.roomName,
    required this.description,
    required this.anchorID,
    required this.anchorFaceURL,
    this.onRefresh,
    this.fullscreen = false,
  });

  final bool loading, active, muted, fullscreen;
  final String message, roomName, description, anchorID, anchorFaceURL;
  final VoidCallback onClose, onFullscreen;
  final VoidCallback? onRefresh, onMute;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: LiveStyle.screen,
        child: Stack(fit: StackFit.expand, children: [
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox.square(
                    dimension: LiveStyle.waitingIndicatorSize,
                    child: Center(
                      child: loading
                          ? const SizedBox.square(
                              dimension: LiveStyle.waitingProgressSize,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: LiveStyle.screenInk,
                              ),
                            )
                          : Icon(active ? Icons.sensors : Icons.live_tv,
                              color: LiveStyle.screenInk.withValues(alpha: .7),
                              size: LiveStyle.waitingIndicatorSize),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: LiveStyle.screenInk, fontSize: 15)),
                  // Loading retains the measured button size, even at big text.
                  Visibility(
                    visible: !loading && onRefresh != null,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: TextButton(
                      onPressed: loading ? null : onRefresh,
                      child: const Text('刷新状态'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 8,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const LiveCastButton(),
              IconButton(
                tooltip: muted ? '打开声音' : '静音',
                onPressed: onMute,
                icon: Icon(
                    muted
                        ? Icons.volume_off_outlined
                        : Icons.volume_up_outlined,
                    color: LiveStyle.screenInk,
                    size: LiveStyle.controlIconSize),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: onClose,
                icon: const Icon(Icons.close, color: LiveStyle.screenInk),
              ),
            ]),
          ),
          Positioned(
            bottom: 10,
            left: 12,
            right: 12,
            child: LiveWatchingBottomBar(
              roomName: roomName,
              description: description,
              anchorID: anchorID,
              anchorFaceURL: anchorFaceURL,
              fullscreen: fullscreen,
              onFullscreen: onFullscreen,
            ),
          ),
        ]),
      );
}
