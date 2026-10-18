import 'package:flutter/material.dart';

import '../media_preview_glass.dart';

/// Shared glass treatment and feedback for viewer icon and text actions.
class MediaPreviewActionButton extends StatelessWidget {
  const MediaPreviewActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final diameter =
        (MediaQuery.sizeOf(context).width * 0.105).clamp(48.0, 52.0);
    return MediaPreviewGlass(
      borderRadius: BorderRadius.circular(diameter / 2),
      interactive: onPressed != null,
      child: icon != null
          ? SizedBox.square(
              dimension: diameter,
              child: IconButton.filled(
                tooltip: label,
                onPressed: onPressed,
                icon: Icon(icon, size: diameter * 0.48),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                ),
              ),
            )
          : TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                minimumSize: Size(diameter, diameter),
              ),
              child: Text(label),
            ),
    );
  }
}
