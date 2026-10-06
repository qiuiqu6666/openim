import 'package:flutter/material.dart';

import '../official_account_chrome_tokens.dart';

/// The reference's blank single-line input area, including the gesture inset.
class OfficialAccountInputSpacer extends StatelessWidget {
  const OfficialAccountInputSpacer({super.key, required this.backgroundColor});

  static const inputBarHeight = OfficialAccountChromeTokens.inputBarHeight;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: backgroundColor,
        child: const SafeArea(
          top: false,
          left: false,
          right: false,
          child: SizedBox(height: inputBarHeight, width: double.infinity),
        ),
      );
}
