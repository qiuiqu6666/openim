import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Shared main-tab title treatment used by top-level pages such as Mine/Wallet.
///
/// Keeping the title and the line-dot indicator in one widget prevents the
/// selected-tab accent, sizing, and spacing from drifting between tabs.
class MainTabTitle extends StatelessWidget {
  const MainTabTitle({
    super.key,
    required this.title,
    required this.color,
    this.titleKey,
    this.indicatorLineKey,
    this.indicatorDotKey,
  });

  final String title;
  final Color color;
  final Key? titleKey;
  final Key? indicatorLineKey;
  final Key? indicatorDotKey;

  @override
  Widget build(BuildContext context) => Transform.translate(
        offset: const Offset(0, AppTokens.mainTabTitleVerticalOffset),
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key: titleKey,
                title,
                style: TextStyle(
                  color: color,
                  fontSize: AppTokens.mainTabTitleFontSize,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(height: AppTokens.mainTabIndicatorTitleGap),
              Transform.translate(
                offset: const Offset(0, -2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      key: indicatorLineKey,
                      width: AppTokens.mainTabIndicatorWidth,
                      height: AppTokens.mainTabIndicatorHeight,
                      decoration: BoxDecoration(
                        color: AppTokens.accent,
                        borderRadius: BorderRadius.circular(AppTokens.rPill),
                      ),
                    ),
                    const SizedBox(width: AppTokens.mainTabIndicatorGap),
                    Container(
                      key: indicatorDotKey,
                      width: AppTokens.mainTabIndicatorDotSize,
                      height: AppTokens.mainTabIndicatorDotSize,
                      decoration: BoxDecoration(
                        color: AppTokens.accent.withValues(alpha: 0.78),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
