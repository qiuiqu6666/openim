import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../widgets/empty_state/illustrated_empty_state.dart';

/// Returns a ScrollView directly so SmartRefresher can reuse its slivers.
CustomScrollView contactListPlaceholder(
  BuildContext context, {
  required String title,
  required bool loading,
  required bool failed,
  required VoidCallback onRetry,
}) {
  final chinese = Localizations.localeOf(context).languageCode == 'zh';
  return CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      SliverFillRemaining(
        hasScrollBody: false,
        child: loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTokens.accent))
            : IllustratedEmptyState(
                icon: Icons.inbox_outlined,
                title: failed
                    ? (chinese ? '加载失败，请重试' : 'Could not load. Please retry.')
                    : title,
                actionLabel: failed ? (chinese ? '重试' : 'Retry') : null,
                onAction: failed ? onRetry : null,
              ),
      ),
    ],
  );
}
