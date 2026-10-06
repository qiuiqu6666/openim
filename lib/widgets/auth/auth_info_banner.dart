import 'package:flutter/material.dart';

import 'auth_reference_tokens.dart';

/// Shared informational banner from 99chat's secondary authentication forms.
class AuthInfoBanner extends StatelessWidget {
  const AuthInfoBanner({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AuthReferenceTokens.bannerPadding),
        decoration: BoxDecoration(
          color: AuthReferenceTokens.brand50,
          borderRadius: BorderRadius.circular(AuthReferenceTokens.bannerRadius),
          border: Border.all(color: AuthReferenceTokens.brand100),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: AuthReferenceTokens.brand500,
                size: AuthReferenceTokens.bannerIcon),
            const SizedBox(width: AuthReferenceTokens.bannerIconGap),
            Expanded(
              child: Text(text, style: AuthReferenceTokens.bannerText),
            ),
          ],
        ),
      );
}
