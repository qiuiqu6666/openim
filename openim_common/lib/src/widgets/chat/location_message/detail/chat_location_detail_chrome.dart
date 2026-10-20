import 'package:flutter/material.dart';
import '../../../../res/app_tokens.dart';
import '../../../liquid_glass_surface.dart';
import '../chat_location_message_data.dart';
import 'chat_location_detail_labels.dart';
import 'chat_location_detail_tokens.dart';

/// Floating glass uses refraction; navigation's flat top treatment does not.
class ChatLocationDetailSurface extends StatelessWidget {
  const ChatLocationDetailSurface(
      {super.key, required this.child, this.blue = false});
  final Widget child;
  final bool blue;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final corners = BorderRadius.circular(ChatLocationDetailTokens.cardRadius);
    return LiquidGlassSurface(
        surface: NavigationGlassSurface.floating,
        preferLiquid: true,
        borderRadius: corners,
        tint: blue
            ? ChatLocationDetailTokens.routeTint
            : AppTokens.surface(dark: dark),
        opacity: blue
            ? ChatLocationDetailTokens.blueSurfaceOpacity
            : dark
                ? ChatLocationDetailTokens.darkSurfaceOpacity
                : ChatLocationDetailTokens.surfaceOpacity,
        child: DecoratedBox(
            decoration: BoxDecoration(
                borderRadius: corners,
                border: Border.all(
                    width: ChatLocationDetailTokens.edgeWidth,
                    color: AppTokens.onAccent.withValues(
                        alpha: ChatLocationDetailTokens.edgeOpacity))),
            child: Material(type: MaterialType.transparency, child: child)));
  }
}

/// Keep Material focus/semantics and animate only the small glass surface.
class _GlassPress extends StatefulWidget {
  const _GlassPress({required this.child, required this.enabled});
  final Widget child;
  final bool enabled;
  @override
  State<_GlassPress> createState() => _GlassPressState();
}

class _GlassPressState extends State<_GlassPress> {
  bool _pressed = false;
  void _press(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context) ||
        View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
    return Listener(
        onPointerDown: widget.enabled ? (_) => _press(true) : null,
        onPointerUp: (_) => _press(false),
        onPointerCancel: (_) => _press(false),
        child: AnimatedScale(
            scale: !reduced && widget.enabled && _pressed
                ? ChatLocationDetailTokens.pressedScale
                : 1,
            duration: reduced
                ? Duration.zero
                : ChatLocationDetailTokens.pressDuration,
            curve: Curves.easeOutCubic,
            child: widget.child));
  }
}

class ChatLocationDetailControl extends StatelessWidget {
  const ChatLocationDetailControl(
      {super.key,
      required this.label,
      required this.icon,
      this.onPressed,
      this.busy = false});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  @override
  Widget build(BuildContext context) => _GlassPress(
      enabled: onPressed != null,
      child: ChatLocationDetailSurface(
          child: SizedBox.square(
              dimension: ChatLocationDetailTokens.controlSize,
              child: IconButton(
                  tooltip: label,
                  onPressed: onPressed,
                  color: AppTokens.textPrimary(
                      dark: Theme.of(context).brightness == Brightness.dark),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: AppTokens.s6,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(icon)))));
}

class ChatLocationDetailCard extends StatelessWidget {
  const ChatLocationDetailCard(
      {super.key,
      required this.data,
      required this.title,
      required this.onDirections,
      this.addressStatus,
      this.onRetryAddress});
  final ChatLocationMessageData data;
  final String title;
  final VoidCallback? onDirections;
  final String? addressStatus;
  final VoidCallback? onRetryAddress;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ChatLocationDetailSurface(
        child: Padding(
            padding: const EdgeInsets.all(AppTokens.s5),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const ExcludeSemantics(
                        child: ChatLocationDetailSurface(
                            blue: true,
                            child: SizedBox.square(
                                dimension: ChatLocationDetailTokens.controlSize,
                                child: Icon(Icons.location_on_outlined,
                                    color: AppTokens.onAccent)))),
                    const SizedBox(width: AppTokens.s4),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: ChatLocationDetailTokens.titleSize,
                                  fontWeight: FontWeight.w600,
                                  color: AppTokens.textPrimary(dark: dark))),
                          if (data.address.isNotEmpty ||
                              addressStatus != null) ...[
                            const SizedBox(height: AppTokens.s2),
                            Text(
                                data.address.isNotEmpty
                                    ? data.address
                                    : addressStatus!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize:
                                        ChatLocationDetailTokens.addressSize,
                                    color: AppTokens.textPrimary(dark: dark))),
                          ],
                        ])),
                  ]),
                  if (onRetryAddress != null)
                    Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                            onPressed: onRetryAddress,
                            child: Text(ChatLocationDetailLabels.of(context)
                                .retryAddress))),
                  const SizedBox(height: AppTokens.s5),
                  _GlassPress(
                      enabled: onDirections != null,
                      child: ChatLocationDetailSurface(
                          blue: true,
                          child: TextButton(
                              key: const ValueKey(
                                  'chat-location-detail-directions'),
                              onPressed: onDirections,
                              style: TextButton.styleFrom(
                                  foregroundColor: AppTokens.onAccent,
                                  minimumSize: const Size(
                                      0, ChatLocationDetailTokens.buttonHeight),
                                  shape: const StadiumBorder(),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppTokens.s5,
                                      vertical: AppTokens.s4)),
                              child: Text(
                                  ChatLocationDetailLabels.of(context)
                                      .directions,
                                  style: const TextStyle(
                                      fontSize:
                                          ChatLocationDetailTokens.titleSize,
                                      fontWeight: FontWeight.w600))))),
                ])));
  }
}
