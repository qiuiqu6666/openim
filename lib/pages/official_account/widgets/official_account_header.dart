import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../chat/chat_logic.dart';
import '../official_account_chrome_tokens.dart';
import 'official_account_name_label.dart';

/// Reference mobile header: avatar, verified name, optional online subtitle.
/// The identity is intentionally a passive surface.
class OfficialAccountHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const OfficialAccountHeader({
    super.key,
    required this.logic,
    this.toolbarHeight = OfficialAccountChromeTokens.toolbarHeight,
  });

  final ChatLogic logic;
  final double toolbarHeight;

  static double heightFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return math.max(
        OfficialAccountChromeTokens.toolbarHeight,
        scaler.scale(OfficialAccountChromeTokens.nameFontSize) *
                OfficialAccountChromeTokens.nameLineHeight +
            scaler.scale(OfficialAccountChromeTokens.subtitleFontSize) *
                OfficialAccountChromeTokens.subtitleLineHeight +
            OfficialAccountChromeTokens.subtitleGap +
            OfficialAccountChromeTokens.headerVerticalPadding * 2);
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + ChatComposerTokens.dividerWidth);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      centerTitle: false,
      titleSpacing: 0,
      leadingWidth: OfficialAccountChromeTokens.leadingWidth,
      toolbarHeight: toolbarHeight,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      backgroundColor: ChatComposerTokens.surface(dark: dark),
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        color: AppTokens.accent,
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(ChatComposerTokens.dividerWidth),
        child: ColoredBox(
          color: ChatComposerTokens.divider(dark: dark),
          child: const SizedBox(
              height: ChatComposerTokens.dividerWidth, width: double.infinity),
        ),
      ),
      title: ListenableBuilder(
        listenable: FriendDisplayPreferences.changes,
        builder: (context, _) => Obx(() {
          final name =
              logic.officialAccount?.displayName ?? logic.nickname.value;
          return Padding(
            padding: const EdgeInsets.symmetric(
                vertical: OfficialAccountChromeTokens.headerVerticalPadding),
            child: Row(
              children: [
                AvatarView(
                  width: OfficialAccountChromeTokens.avatarSize,
                  height: OfficialAccountChromeTokens.avatarSize,
                  url: logic.faceUrl.value,
                  text: name,
                  isCircle: true,
                  textStyle: TextStyle(
                      color: AppTokens.onAccent,
                      fontFamily:
                          Theme.of(context).textTheme.bodyMedium?.fontFamily,
                      fontSize: OfficialAccountChromeTokens.avatarTextSize),
                  textScaler: TextScaler.noScaling,
                ),
                const SizedBox(width: OfficialAccountChromeTokens.avatarGap),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OfficialAccountNameLabel(
                        name: name,
                        userID: logic.userID,
                        ex: logic.conversationInfo.ex,
                        account: logic.officialAccount,
                        badgeSize: OfficialAccountChromeTokens.badgeSize,
                        style: TextStyle(
                            inherit: false,
                            fontFamily: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.fontFamily,
                            color: AppTokens.textPrimary(dark: dark),
                            fontSize: OfficialAccountChromeTokens.nameFontSize,
                            fontWeight: OfficialAccountChromeTokens.nameWeight,
                            height: OfficialAccountChromeTokens.nameLineHeight,
                            leadingDistribution: TextLeadingDistribution.even),
                      ),
                      if (FriendDisplayPreferences.showOnlineStatus) ...[
                        const SizedBox(
                            height: OfficialAccountChromeTokens.subtitleGap),
                        Text(StrRes.online,
                            maxLines: 1,
                            style: TextStyle(
                                inherit: false,
                                fontFamily: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.fontFamily,
                                color: AppTokens.accent,
                                fontSize: OfficialAccountChromeTokens
                                    .subtitleFontSize,
                                height: OfficialAccountChromeTokens
                                    .subtitleLineHeight)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
