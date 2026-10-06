import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Logical-pixel values from 99chat's Moments widgets and semantic palette.
abstract final class MomentsLayout {
  static const pageMaxWidth = 640.0;
  static const coverHeight = 250.0;
  static const headerHeight = 250.0;
  static const avatarSize = 40.0;
  static const detailAvatarSize = 44.0;
  static const headerAvatarSize = 72.0;
  static const headerAvatarTop = 150.0;
  static const cardRadius = 18.0;
  static const cardMargin = 10.0;
  static const cardPadding = EdgeInsets.fromLTRB(14, 12, 14, 6);
  static const bodySize = 15.0;
  static const nameSize = 16.0;
  // These retain the existing like and comment button label sizes.
  static const captionSize = AppTokens.captionFontSize;
  static const timeSize = 12.0;
  static const spacing = AppTokens.s5;
  static const touchTarget = 48.0;
  // CupertinoSwitch includes its visual padding in this layout box.
  static const privacyToggleSize = Size(59, 39);
  static const mediaGap = 4.0;
  static const mediaRadius = 12.0;
  static const mediaTileRadius = 6.0;
  static const footerSpace = 24.0;
  static const iconSize = AppTokens.chevronSize;
  static const textHeight = 1.5;
  static const coverAsset = 'assets/images/moments_cover_99chat.webp';
  static const timelineDateWidth = 64.0;
  static const timelineGap = 12.0;
  static const timelineMediaSize = 104.0;
  static const timelinePadding = EdgeInsets.fromLTRB(16, 14, 16, 14);
}

abstract final class MomentsTheme {
  static Color background(bool dark) =>
      dark ? const Color(0xFF101114) : const Color(0xFFF5F6F8);
  static Color card(bool dark) =>
      dark ? const Color(0xFF1B1D22) : const Color(0xFFFFFFFF);
  static Color panel(bool dark) =>
      dark ? const Color(0xFF23262D) : const Color(0xFFF1F3F5);
  static Color text(bool dark) =>
      dark ? const Color(0xFFF4F4F4) : const Color(0xFF1C1C1E);
  static Color secondary(bool dark) =>
      dark ? const Color(0xFF9A9CA3) : const Color(0xFF7B8491);
  static Color border(bool dark) =>
      dark ? const Color(0xFF2A2D33) : const Color(0xFFE6E8EC);
  static Color name(bool dark) => dark ? text(dark) : const Color(0xFF374151);
  static Color nav(bool dark) => name(dark);
  static Color icon(bool dark) => secondary(dark);
  static Color detailBackground(bool dark) =>
      dark ? background(dark) : card(dark);
  static Color composerTile(bool dark) =>
      dark ? const Color(0xFF22252B) : const Color(0xFFF6F6F6);
  static Color composerIcon(bool dark) =>
      dark ? secondary(dark).withValues(alpha: .55) : const Color(0xFFD0D0D0);
  static const coverForeground = Color(0xFFFFFFFF);
  static const coverSecondary = Color(0xB3FFFFFF);
  static const coverShadow = Color(0x42000000);
  static const coverFallback = Color(0xFF3A3A3A);
  static const notificationBadge = Color(0xFFE60022);
  static const mediaBadge = Color(0x8A000000);
  static const collageOverlay = Color(0x6B000000);
}
