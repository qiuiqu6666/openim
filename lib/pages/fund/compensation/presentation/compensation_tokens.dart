import 'package:flutter/material.dart';

abstract final class CompensationTokens {
  static const gap = 8.0,
      small = 4.0,
      space = 16.0,
      inset = 20.0,
      radius = 12.0;
  static const maxWidth = 520.0,
      title = 30.0,
      body = 14.0,
      label = 12.0,
      amount = 36.0;
  static const cardRadius = 24.0,
      resultAmount = 44.0,
      resultIllustration = 132.0;
  static const campaignHeadline = 38.0, rewardAmount = 40.0;
  static const detailBackground =
      'assets/images/compensation_detail_background.png';
  static const silverTop = Color(0xFFE2E2E2), silverBottom = Color(0xFF999999);
  static const silverInk = Color(0xFF393939);
  static Color ink(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? posterText
      : const Color(0xFF621F0E);
  static Color panel(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? const Color(0xFF321C20)
          : const Color(0xFFFFF9F0);
  static const homeBannerHeight = 60.0;
  static const heroHeight = 184.0, heroWidth = 224.0, touch = 48.0;
  static const red = Color(0xFFD90019),
      button = Color(0xFFD90019),
      gold = Color(0xFFFFD184);
  static const posterTop = Color(0xFFB81E35),
      posterBottom = Color(0xFF711326),
      posterText = Color(0xFFFFF3DF);
  static const posterTitle = 22.0,
      posterAmount = 26.0,
      posterIllustration = 100.0;
  static const invitationWidth = 420.0, invitationFinePrint = 10.0;
  static const invitationHighlight = Color(0xFFFFE5A0),
      invitationInk = Color(0xFF8B120A);
  static const invitationBackground =
      'assets/images/compensation_invitation_template.png';
  static const closedAsset = 'assets/images/compensation_upright_closed.png';
  static const openAsset = 'assets/images/compensation_upright_open.png';
  static const homeBanner =
      'assets/images/compensation_home_banner_2160x360.png';
  static const walletBanner = 'assets/images/compensation_wallet_banner.png';
  static const poster = 'assets/images/compensation_popup_gift.png';
  static Color accent(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? const Color(0xFFFF9C9C) : red;
  static Color cream(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? const Color(0xFF321C20)
          : const Color(0xFFFFF1E1);
  static Color tint(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? const Color(0xFF46242A)
      : const Color(0xFFFFE6E6);
}
