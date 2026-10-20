import 'package:flutter/material.dart';

import '../../res/app_tokens.dart';

/// Edge shortcut to the retained browser, alongside its bottom dock.
class InAppBrowserReturnButton extends StatelessWidget {
  const InAppBrowserReturnButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.centerRight,
        children: [
          Material(
            color: AppTokens.accent,
            elevation: AppTokens.s2,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(AppTokens.rPill)),
            ),
            clipBehavior: Clip.antiAlias,
            child: const SizedBox(
              width: AppTokens.minimumTapSize,
              height: ChatScrollHintTokens.minHeight,
            ),
          ),
          Semantics(
            label: Localizations.localeOf(context).languageCode == 'zh'
                ? '返回网页'
                : 'Return to web page',
            child: IconButton(
              onPressed: onPressed,
              color: AppTokens.onAccent,
              iconSize: ChatScrollHintTokens.iconSize,
              constraints: const BoxConstraints(
                  minWidth: AppTokens.minimumTapSize,
                  minHeight: AppTokens.minimumTapSize),
              icon: const Icon(Icons.language),
            ),
          ),
        ],
      );
}
