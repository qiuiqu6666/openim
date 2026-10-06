import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart' hide MainTabTitle;

import 'mine_decorative_background.dart';
import 'mine_hot_eco.dart';
import 'mine_menu_section.dart';
import 'mine_profile_header.dart';
import 'mine_profile_localization.dart';
import '../../home/widgets/main_tab_title.dart';

class MineProfileView extends StatelessWidget {
  const MineProfileView({
    super.key,
    required this.nickname,
    required this.userId,
    required this.avatarUrl,
    this.avatarBytes,
    required this.signature,
    required this.onProfileTap,
    required this.onQrTap,
    required this.onFavoritesTap,
    required this.onCallsTap,
    required this.onNotificationsTap,
    required this.onShareAppTap,
    required this.onSettingsTap,
    required this.onFeatureTap,
    this.onWalletTap,
    required this.onUnavailableFeatureTap,
  });

  final String nickname;
  final String userId;
  final String avatarUrl;
  final Uint8List? avatarBytes;
  final String signature;
  final VoidCallback onProfileTap;
  final VoidCallback onQrTap;
  final VoidCallback onFavoritesTap;
  final VoidCallback onCallsTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onShareAppTap;
  final VoidCallback onSettingsTap;
  final ValueChanged<String> onFeatureTap;
  final VoidCallback? onWalletTap;
  final ValueChanged<String> onUnavailableFeatureTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTokens.textPrimary(dark: dark);
    final secondary = AppTokens.textSecondary(dark: dark);
    final dividerBase = dark ? AppTokens.borderDark : const Color(0xFFEAEAEA);
    final divider = dividerBase.withValues(alpha: 0.42);
    final card = AppTokens.surface(dark: dark).withValues(
      alpha: dark
          ? AppTokens.profileSectionDarkOpacity
          : AppTokens.profileSectionLightOpacity,
    );
    final displayName = nickname.trim().isNotEmpty
        ? nickname.trim()
        : (userId.trim().isNotEmpty
            ? userId.trim()
            : mineText(context, zh: '未设置', en: 'Not set'));
    final displayUserId = userId.trim().isEmpty ? '--' : userId.trim();
    final displaySignature = signature.trim().isEmpty
        ? mineText(context, zh: '未设置', en: 'Not set')
        : signature.trim();
    final overlay = AppSystemBars.styleFor(AppTokens.background(dark: dark));
    final screenWidth = MediaQuery.sizeOf(context).width;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.0),
      ),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: Scaffold(
          backgroundColor: AppTokens.background(dark: dark),
          extendBody: false,
          extendBodyBehindAppBar: true,
          appBar: GlassAppBar(
            toolbarHeight: kToolbarHeight,
            key: const ValueKey('mine-main-appbar'),
            elevation: 0,
            scrolledUnderElevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            backgroundColor: Colors.transparent,
            iconTheme: IconThemeData(color: primary),
            actionsIconTheme: IconThemeData(color: primary),
            automaticallyImplyLeading: false,
            centerTitle: false,
            titleSpacing: 16,
            systemOverlayStyle: overlay,
            flexibleSpace: MineTopSparkles(dark: dark),
            title: MainTabTitle(
              title: mineText(context, zh: '我的', en: 'Me'),
              color: primary,
              titleKey: const ValueKey('mine-title-text'),
              indicatorLineKey: const ValueKey('mine-title-indicator-line'),
              indicatorDotKey: const ValueKey('mine-title-indicator-dot'),
            ),
            actions: [
              IconButton(
                key: const ValueKey('mine-top-settings'),
                tooltip: mineText(context, zh: '设置', en: 'Settings'),
                onPressed: onSettingsTap,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: AppSettingsGearIcon(
                  size: AppIconTokens.large,
                  color: primary,
                ),
              ),
              SizedBox(width: screenWidth * 0.030),
            ],
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              MineDecorativeBackground(dark: dark),
              SingleChildScrollView(
                key: const PageStorageKey<String>('mine-profile-scroll'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    0,
                    MediaQuery.paddingOf(context).top + kToolbarHeight,
                    0,
                    kBottomNavigationBarHeight +
                        32 +
                        MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MineProfileHeader(
                        nickname: displayName,
                        userId: displayUserId,
                        avatarUrl: avatarUrl,
                        avatarBytes: avatarBytes,
                        signature: displaySignature,
                        primaryTextColor: primary,
                        secondaryTextColor: secondary,
                        arrowColor: secondary,
                        dark: dark,
                        onTap: onProfileTap,
                        onQrTap: onQrTap,
                      ),
                      MineHotEcoSection(
                        primaryTextColor: primary,
                        secondaryTextColor: secondary,
                        arrowColor: secondary,
                        dark: dark,
                        onFeatureTap: onFeatureTap,
                        onWalletTap: onWalletTap,
                        onUnavailableFeatureTap: onUnavailableFeatureTap,
                      ),
                      const SizedBox(height: 14),
                      MineSectionCard(
                        color: card,
                        children: [
                          _menu(
                            key: 'mine-menu-favorites',
                            asset: 'assets/profile_icons/favorites.svg',
                            title: mineText(context, zh: '收藏', en: 'Favorites'),
                            onTap: onFavoritesTap,
                            divider: divider,
                            text: primary,
                            arrow: secondary,
                            showDivider: false,
                          ),
                        ],
                      ),
                      MineSectionCard(
                        color: card,
                        children: [
                          _menu(
                            key: 'mine-menu-calls',
                            asset: 'assets/profile_icons/call.svg',
                            title: mineText(context, zh: '通话', en: 'Calls'),
                            onTap: onCallsTap,
                            divider: divider,
                            text: primary,
                            arrow: secondary,
                          ),
                          _menu(
                            key: 'mine-menu-notifications',
                            asset: 'assets/profile_icons/notification.svg',
                            title: mineText(
                              context,
                              zh: '消息通知',
                              en: 'Notifications',
                            ),
                            onTap: onNotificationsTap,
                            divider: divider,
                            text: primary,
                            arrow: secondary,
                            showDivider: false,
                          ),
                        ],
                      ),
                      MineSectionCard(
                        color: card,
                        children: [
                          _menu(
                            key: 'mine-menu-share-app',
                            asset: 'assets/profile_icons/share_app.svg',
                            title:
                                mineText(context, zh: '分享应用', en: 'Share App'),
                            onTap: onShareAppTap,
                            divider: divider,
                            text: primary,
                            arrow: secondary,
                          ),
                          _menu(
                            key: 'mine-menu-settings',
                            asset: 'assets/profile_icons/settings.svg',
                            title: mineText(context, zh: '设置', en: 'Settings'),
                            onTap: onSettingsTap,
                            divider: divider,
                            text: primary,
                            arrow: secondary,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  MineMenuCell _menu({
    required String key,
    required String asset,
    required String title,
    required VoidCallback onTap,
    required Color divider,
    required Color text,
    required Color arrow,
    bool showDivider = true,
  }) =>
      MineMenuCell(
        key: ValueKey(key),
        assetPath: asset,
        title: title,
        dividerColor: divider,
        textColor: text,
        arrowColor: arrow,
        showDivider: showDivider,
        onTap: onTap,
      );
}
