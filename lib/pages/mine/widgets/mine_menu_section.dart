import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const _assetPackage = 'openim_common';

/// Groups profile actions in an inset, rounded card.
class MineSectionCard extends StatelessWidget {
  const MineSectionCard({
    super.key,
    required this.color,
    required this.children,
  });

  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }
}

/// 1:1 port of 99chat profile.dart `_buildPlainCell` for SVG menu icons.
class MineMenuCell extends StatelessWidget {
  const MineMenuCell({
    super.key,
    required this.assetPath,
    required this.title,
    required this.dividerColor,
    required this.textColor,
    required this.arrowColor,
    required this.onTap,
    this.showDivider = true,
  });

  final String assetPath;
  final String title;
  final Color dividerColor;
  final Color textColor;
  final Color arrowColor;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: dividerColor))
              : null,
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              assetPath,
              package: _assetPackage,
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                assert(() {
                  debugPrint('Profile menu SVG failed: $assetPath $error');
                  return true;
                }());
                return Icon(
                  Icons.image_not_supported_outlined,
                  size: 28,
                  color: Theme.of(context).colorScheme.outline,
                );
              },
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 24,
              color: arrowColor,
            ),
          ],
        ),
      ),
    );
  }
}
