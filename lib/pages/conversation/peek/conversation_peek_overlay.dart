// Adapted from 99chat's conversation_peek_overlay.dart shell and pill header.
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: caller-owned content, menu and actions; guarded route dismissal and a11y sizing.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../official_account/widgets/official_account_name_label.dart';
import 'conversation_peek_layout.dart';

typedef ConversationPeekMenuBuilder = Widget Function(
    BuildContext context, double itemVerticalPadding, VoidCallback dismiss);

class ConversationPeekOverlay {
  ConversationPeekOverlay._();

  static bool _isShowing = false;

  /// Only shows UI. Callers own the history loader and record actions for after
  /// this Future completes, when the outgoing route has actually been removed.
  static Future<void> show({
    required BuildContext context,
    required String displayName,
    String? userID,
    String? ex,
    bool isSingleChat = true,
    Widget? headerSubtitle,
    required Widget messageContent,
    required ConversationPeekMenuBuilder menuBuilder,
    required int menuItemCount,
    int menuDividerCount = 1,
    bool Function()? canOpenChat,
    required VoidCallback onOpenChat,
    VoidCallback? onDismiss,
  }) async {
    if (_isShowing || !context.mounted) return;
    assert(menuItemCount >= 0 && menuDividerCount >= 0);
    _isShowing = true;
    final navigator = Navigator.of(context, rootNavigator: true);
    var closing = false;
    late final RawDialogRoute<void> route;
    void dismiss() {
      if (closing || !route.isCurrent) return;
      closing = true;
      navigator.pop();
    }

    try {
      route = RawDialogRoute<void>(
        barrierDismissible: true,
        barrierLabel: Localizations.localeOf(context).languageCode == 'zh'
            ? '关闭预览'
            : 'Dismiss preview',
        barrierColor: Colors.transparent,
        transitionDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : _PeekStyle.transitionDuration,
        pageBuilder: (context, animation, secondaryAnimation) => _PeekDialog(
          displayName: displayName,
          userID: userID,
          ex: ex,
          isSingleChat: isSingleChat,
          headerSubtitle: headerSubtitle,
          messageContent: messageContent,
          menuBuilder: menuBuilder,
          menuItemCount: menuItemCount,
          menuDividerCount: menuDividerCount,
          onDismiss: dismiss,
          onOpenChat: () {
            if (closing || !route.isCurrent || !(canOpenChat?.call() ?? true)) {
              return;
            }
            dismiss();
            onOpenChat();
          },
        ),
        transitionBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
          child: child,
        ),
      );
      await navigator.push<void>(route);
      await route.completed;
    } finally {
      _isShowing = false;
      onDismiss?.call();
    }
  }
}

class _PeekStyle {
  _PeekStyle._();

  static const transitionDuration = Duration(milliseconds: 220);
  static const blurSigma = 12.0;
  static const scrimOpacity = .35;
  static const cardShadowOpacity = .16;
  static const cardShadowBlur = 28.0;
  static const cardShadowOffset = 10.0;
  static const headerTopGap = 10.0;
  static const headerBodyGap = 6.0;
  static const headerVerticalPadding = 5.0;
  static const subtitleGap = 1.0;
  static const titleFontSize = 13.0;
  static const titleHeight = 1.15;
  static const lightPill = Color(0xFFF2F2F7);

  static Color pill({required bool dark}) =>
      dark ? AppTokens.surfaceAltDark : lightPill;
}

class _PeekDialog extends StatelessWidget {
  const _PeekDialog({
    required this.displayName,
    required this.userID,
    required this.ex,
    required this.isSingleChat,
    required this.headerSubtitle,
    required this.messageContent,
    required this.menuBuilder,
    required this.menuItemCount,
    required this.menuDividerCount,
    required this.onDismiss,
    required this.onOpenChat,
  });

  final String displayName;
  final String? userID;
  final String? ex;
  final bool isSingleChat;
  final Widget? headerSubtitle;
  final Widget messageContent;
  final ConversationPeekMenuBuilder menuBuilder;
  final int menuItemCount;
  final int menuDividerCount;
  final VoidCallback onDismiss;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scrim = ColoredBox(
        color: scheme.scrim.withValues(alpha: _PeekStyle.scrimOpacity));
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('conversation-peek-dismiss'),
              onTap: onDismiss,
              child: defaultTargetPlatform == TargetPlatform.android
                  ? scrim
                  : BackdropFilter(
                      filter: ImageFilter.blur(
                          sigmaX: _PeekStyle.blurSigma,
                          sigmaY: _PeekStyle.blurSigma),
                      child: scrim,
                    ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              final layout = ConversationPeekLayout.resolve(
                constraints: constraints,
                screenWidth: MediaQuery.sizeOf(context).width,
                menuItemCount: menuItemCount,
                menuDividerCount: menuDividerCount,
                textScaler: MediaQuery.textScalerOf(context),
              );
              return Padding(
                padding: EdgeInsets.fromLTRB(
                    layout.horizontalPadding,
                    layout.topPadding,
                    layout.horizontalPadding,
                    layout.bottomPadding),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      key: const ValueKey('conversation-peek-card'),
                      height: layout.previewHeight,
                      child: layout.previewHeight == 0
                          ? null
                          : _buildCard(context, layout),
                    ),
                    SizedBox(height: layout.gap),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        key: const ValueKey('conversation-peek-menu-viewport'),
                        width: layout.menuWidth,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxHeight: layout.menuViewportHeight),
                          child: SingleChildScrollView(
                            primary: false,
                            physics: const ClampingScrollPhysics(),
                            child: menuBuilder(context,
                                layout.menuItemVerticalPadding, onDismiss),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, ConversationPeekMetrics layout) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final topGap = math.min(_PeekStyle.headerTopGap, layout.previewHeight);
    final bodyGap = math.min(
        _PeekStyle.headerBodyGap, math.max(0.0, layout.previewHeight - topGap));
    return GestureDetector(
      onTap: onOpenChat,
      child: Container(
        width: layout.cardWidth,
        decoration: BoxDecoration(
          color: dark ? AppTokens.backgroundDark : AppTokens.surfaceLight,
          borderRadius: BorderRadius.circular(layout.cardRadius),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow
                  .withValues(alpha: _PeekStyle.cardShadowOpacity),
              blurRadius: _PeekStyle.cardShadowBlur,
              offset: const Offset(0, _PeekStyle.cardShadowOffset),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SizedBox(height: topGap),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: layout.previewHeight - topGap - bodyGap),
              child: SingleChildScrollView(
                primary: false,
                child: _buildHeader(dark),
              ),
            ),
            SizedBox(height: bodyGap),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: layout.cardRadius * .35),
                child: messageContent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool dark) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
        child: Center(
          child: Container(
            key: const ValueKey('conversation-peek-title-pill'),
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s4,
                vertical: _PeekStyle.headerVerticalPadding),
            decoration: BoxDecoration(
              color: _PeekStyle.pill(dark: dark),
              borderRadius: BorderRadius.circular(AppTokens.rPill),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OfficialAccountNameLabel(
                  name: displayName,
                  userID: userID,
                  ex: ex,
                  isSingleChat: isSingleChat,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _PeekStyle.titleFontSize,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.textPrimary(dark: dark),
                    height: _PeekStyle.titleHeight,
                  ),
                ),
                if (headerSubtitle != null) ...[
                  const SizedBox(height: _PeekStyle.subtitleGap),
                  headerSubtitle!,
                ],
              ],
            ),
          ),
        ),
      );
}
