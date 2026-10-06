import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../user_profile_tokens.dart';

/// Unknown relationships must not briefly render stranger actions.
class UserProfileLoadState extends StatelessWidget {
  const UserProfileLoadState({
    super.key,
    required this.failed,
    required this.onRetry,
  });

  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top +
            NavigationGlassTokens.toolbarHeight,
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!failed)
            FadingArcSpinner(
              key: const ValueKey('user_profile_loading'),
              size: AppTokens.s7,
              color: AppTokens.accent,
            ),
          const SizedBox(height: AppTokens.s4),
          Text(
            failed
                ? (zh ? '资料加载失败' : 'Could not load profile')
                : (zh ? '正在加载资料' : 'Loading profile'),
            style: TextStyle(color: UserProfileTokens.muted(context)),
          ),
          if (failed)
            TextButton(
              key: const ValueKey('user_profile_retry'),
              onPressed: onRetry,
              child: Text(zh ? '重新加载' : 'Retry'),
            ),
        ]),
      ),
    );
  }
}
