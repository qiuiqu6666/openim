import 'package:flutter/material.dart';

import '../../../../res/app_tokens.dart';
import '../chat_location_picker_labels.dart';
import '../chat_location_picker_tokens.dart';
import '../native/chat_location_native_map_options.dart';

/// Flutter controls stay the same size while native maps render underneath.
class ChatLocationMapOverlay extends StatelessWidget {
  const ChatLocationMapOverlay(
      {super.key,
      required this.map,
      required this.locating,
      required this.active,
      required this.failure,
      required this.onLocate});

  final Widget map;
  final bool locating, active;
  final ChatLocationMapFailure? failure;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labels = ChatLocationPickerLabels.of(context);
    final surface = AppTokens.surface(dark: dark);
    return Stack(fit: StackFit.expand, children: [
      ClipRect(
          child: KeyedSubtree(
              key: const ValueKey('chat-location-map'), child: map)),
      if (failure == null && (active || locating)) ...[
        Positioned(
            top: AppTokens.s5,
            left: AppTokens.s5,
            right: AppTokens.s5,
            child: IgnorePointer(
                child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth: ChatLocationPickerTokens.hintMaxWidth),
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: surface,
                                borderRadius:
                                    BorderRadius.circular(AppTokens.rPill)),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppTokens.s5,
                                    vertical: AppTokens.s3),
                                child: Text(
                                    locating ? labels.locating : labels.mapHint,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color:
                                            AppTokens.textPrimary(dark: dark),
                                        fontSize: ChatLocationPickerTokens
                                            .captionSize)))))))),
        Positioned(
            bottom: AppTokens.s5,
            right: AppTokens.s5,
            child: Material(
                color: surface,
                shape: const CircleBorder(),
                child: SizedBox.square(
                    dimension: ChatLocationPickerTokens.touchSize,
                    child: IconButton(
                        key: const ValueKey('chat-location-locate'),
                        tooltip: locating ? labels.locating : labels.locate,
                        onPressed: active && !locating ? onLocate : null,
                        color: AppTokens.accent,
                        disabledColor: AppTokens.textSecondary(dark: dark),
                        icon: locating
                            ? const SizedBox.square(
                                dimension:
                                    ChatLocationPickerTokens.controlIconSize,
                                child: CircularProgressIndicator(
                                    color: AppTokens.accent,
                                    strokeWidth: ChatLocationPickerTokens
                                        .progressStroke))
                            : const Icon(Icons.my_location_rounded,
                                size: ChatLocationPickerTokens
                                    .controlIconSize))))),
      ],
    ]);
  }
}
