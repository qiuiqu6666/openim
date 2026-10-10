import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

/// Reuse the refresh package's states without spinning while the list is idle.
Widget groupApplicationFooter(BuildContext context) {
  final strings = RefreshLocalizations.of(context)?.currentLocalization ??
      (Localizations.localeOf(context).languageCode == 'zh'
          ? ChRefreshString()
          : EnRefreshString());
  return ClassicFooter(
    textStyle: (Theme.of(context).textTheme.bodySmall ??
            DefaultTextStyle.of(context).style)
        .copyWith(
      color: AppTokens.textSecondary(
          dark: Theme.of(context).brightness == Brightness.dark),
    ),
    idleText: strings.idleLoadingText,
    loadingText: strings.loadingText,
    canLoadingText: strings.canLoadingText,
    failedText: strings.loadFailedText,
    noDataText: strings.noMoreText,
  );
}
