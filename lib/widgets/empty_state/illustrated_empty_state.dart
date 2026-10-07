import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Shared 99chat illustration for empty lists and recoverable errors.
class IllustratedEmptyState extends StatelessWidget {
  const IllustratedEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description = '',
    this.actionLabel,
    this.onAction,
    this.imageWidth = 160,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double imageWidth;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary = AppTokens.textSecondary(dark: dark);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s8, vertical: AppTokens.s8 + AppTokens.s3),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/empty_99chat.webp',
              package: 'openim_common',
              width: imageWidth,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => Icon(
                icon,
                size: imageWidth * 0.45,
                color: secondary.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: AppTokens.s5),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: secondary,
                fontSize: AppTokens.secondaryFontSize,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
            if (description.trim().isNotEmpty) ...[
              const SizedBox(height: AppTokens.s3),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary, fontSize: 13, height: 1.45),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppTokens.s5),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    color: AppTokens.accent,
                    fontSize: AppTokens.captionFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
