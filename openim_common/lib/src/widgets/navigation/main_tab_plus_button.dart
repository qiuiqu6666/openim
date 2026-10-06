// Plus action adapted from 99chat's home_page.dart (Apache License 2.0).
// Source: https://github.com/qiuiqu6666/99chat
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../res/app_tokens.dart';

/// Shared main-tab plus action. The actual IconButton owns its menu anchor key.
class MainTabPlusButton extends StatelessWidget {
  const MainTabPlusButton({
    super.key,
    this.buttonKey,
    required this.onPressed,
    this.turns = 0,
    this.reducedMotion = false,
  });

  final Key? buttonKey;
  final VoidCallback? onPressed;
  final double turns;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final disableMotion = reducedMotion ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    return IconButton(
      key: buttonKey,
      tooltip: zh ? '添加' : 'Add',
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.standard,
      constraints: const BoxConstraints.tightFor(
        width: kMinInteractiveDimension,
        height: kMinInteractiveDimension,
      ),
      icon: AnimatedRotation(
        turns: turns,
        duration:
            disableMotion ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: SizedBox.square(
          dimension: AppTokens.s7,
          child: Image.asset(
            'assets/images/home_nav_plus_99chat.png',
            package: 'openim_common',
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => SvgPicture.string(
              _plusIconSvg,
              key: const ValueKey('conversation-plus-fallback'),
              width: AppTokens.s7,
              height: AppTokens.s7,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

// The reference PNG is a 200px rounded cross with a 22px stroke. Keep the
// same shape available during an old bundle's hot reload or a decode failure.
const _plusIconSvg = '''
<svg viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
  <path d="M100 11V189M11 100H189" fill="none" stroke="#1E90FF"
        stroke-width="22" stroke-linecap="round"/>
</svg>
''';
