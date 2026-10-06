import 'package:flutter/material.dart';

/// Shared visual tokens aligned with the 99chat product surfaces.
///
/// New pages should consume these semantic tokens instead of scattering raw
/// colors and dimensions through page code. Existing OpenIM screens can keep
/// using [Styles] until they are migrated.
class AppTokens {
  AppTokens._();

  // Semantic colors.
  static const Color accent = Color(0xFF1E90FF);
  static const Color ink600 = Color(0xFF374151);
  static const Color danger = Color(0xFFDC2626);
  static const Color walletDanger = Color(0xFFE60022);
  static const Color paymentErrorDark = Color(0xFFFF6B73);
  static const Color success = Color(0xFF059669);
  static const Color biometricGreen = Color(0xFF07C160);
  static const Color warning = Color(0xFFD97706);
  static const Color backgroundLight = Color(0xFFF5F6F8);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceAltLight = Color(0xFFF1F3F5);
  static const Color textPrimaryLight = Color(0xFF1C1C1E);
  static const Color textSecondaryLight = Color(0xFF7B8491);
  static const Color borderLight = Color(0xFFE6E8EC);

  static const Color backgroundDark = Color(0xFF101114);
  static const Color surfaceDark = Color(0xFF1B1D22);
  static const Color surfaceAltDark = Color(0xFF23262D);
  static const Color textPrimaryDark = Color(0xFFF4F4F4);
  static const Color textSecondaryDark = Color(0xFF9A9CA3);
  static const Color borderDark = Color(0xFF2A2D33);

  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color profileSignatureBgLight = Color(0xFFEDEBFF);
  static const Color profileSignatureBgDark = Color(0xFF5D74F2);
  static const Color profileSignatureTextLight = Color(0xFF5D74F2);
  static const Color profileSignatureTextDark = Color(0xFFA8B4FF);
  static const Color decorativeSparkle = Color(0xFF8EBBFF);
  static const Color profileEcoGlowLight = Color(0xFFF2DFFF);
  static const Color profileEcoGlowDark = Color(0xFF6B4A9A);

  static const double profileSectionLightOpacity = 0.72;
  static const double profileSectionDarkOpacity = 0.94;

  static const List<Color> decorativeGradientLight = [
    Color(0xFFFCFCFE),
    Color(0xFFFAF9FD),
    Color(0xFFFAFBFC),
  ];
  static const List<Color> decorativeGradientDark = [
    Color(0xFF1C1830),
    Color(0xFF171A24),
    Color(0xFF131820),
    Color(0xFF101114),
  ];
  static const List<double> decorativeGradientDarkStops = [0, 0.36, 0.72, 1];

  static Color background({required bool dark}) =>
      dark ? backgroundDark : backgroundLight;
  static Color surface({required bool dark}) =>
      dark ? surfaceDark : surfaceLight;
  static Color surfaceAlt({required bool dark}) =>
      dark ? surfaceAltDark : surfaceAltLight;
  static Color textPrimary({required bool dark}) =>
      dark ? textPrimaryDark : textPrimaryLight;
  static Color textSecondary({required bool dark}) =>
      dark ? textSecondaryDark : textSecondaryLight;
  static Color border({required bool dark}) => dark ? borderDark : borderLight;
  static Color paymentError({required bool dark}) =>
      dark ? paymentErrorDark : walletDanger;

  // 4pt spacing scale used by 99chat surfaces.
  static const double s2 = 4;
  static const double s3 = 8;
  static const double s4 = 12;
  static const double s5 = 16;
  static const double s6 = 20;
  static const double s7 = 24;
  static const double s8 = 32;

  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 14;
  static const double rPill = 999;

  static const double listItemHeight = 56;
  static const double mainTabTitleFontSize = 22;
  static const double mainTabTitleVerticalOffset = -2;
  static const double mainTabTitleDesktopFontSize = 20;
  static const double profileNameFontSize = 19;
  static const double listTitleFontSize = 17;
  static const double secondaryFontSize = 15;
  static const double captionFontSize = 14;
  static const double profileAvatarSize = 72;
  static const double profileMenuIconSize = 28;
  static const double profileQrIconSize = 20;
  static const double mainTabIndicatorWidth = 32;
  static const double mainTabIndicatorDesktopWidth = 36;
  static const double mainTabIndicatorHeight = 4;
  static const double mainTabIndicatorDotSize = 8;
  static const double mainTabIndicatorGap = 8;
  static const double mainTabIndicatorTitleGap = 2;
  static const double chevronSize = 24;
}

/// Conversation media grid geometry from 99chat's media/file browser.
class ChatHistoryMediaTokens {
  ChatHistoryMediaTokens._();

  static const double gap = 2;
  static const double wideBreakpoint = 480;
  static const int compactColumns = 3;
  static const int wideColumns = 4;
  static const double playIconSize = 28;
  static const double playIconOpacity = .7;
}

/// Shared favorite audio preview geometry for management and chat pickers.
class FavoriteMediaTokens {
  FavoriteMediaTokens._();

  static const double audioWidth = 144;
  static const double audioHeight = 48;
}

/// Favorite picker layout and row action from 99chat's picker sheet.
class FavoritePickerTokens {
  FavoritePickerTokens._();

  static const double sheetHeightFactor = .78;
  static const Duration contentTransitionDuration = Duration(milliseconds: 180);
  static const Curve contentTransitionCurve = Curves.easeOutCubic;
  static const double footerHeight = 56;
  static const double compactControlsHeight = 280;
  static const double sheetRadius = 24;
  static const double handleWidth = 38;
  static const double handleHeight = 5;
  static const double handleRadius = 3;
  static const double titleSize = 24;
  static const double headerLeftPadding = 18;
  static const double closeIconSize = 27;
  static const double toolbarIconSize = 26;
  static const double cardRadius = 16;
  static const double cardGap = 10;
  static const double listPadding = 14;
  static const double textThumbnailSize = 36;
  static const double textThumbnailRadius = 10;
  static const double mediaWidth = 76;
  static const double mediaHeight = 68;
  static const double previewFontSize = 15;
  static const double metadataFontSize = 12;
  static const double footerFontSize = 13;
  static const double previewLineHeight = 1.4;
  static const double sourceGap = 7;
  static const double dateGap = 5;
  static const double chipHorizontalPadding = 9;
  static const Color thumbnailIcon = Color(0xFF568EFF);
  static Color handle({required bool dark}) =>
      dark ? const Color(0xFF555D6B) : const Color(0xFFD1D7E1);
  static Color card({required bool dark}) =>
      dark ? const Color(0xFF252A33) : const Color(0xFFF6F8FB);
  static Color chip({required bool dark}) =>
      dark ? const Color(0xFF292D35) : const Color(0xFFF2F4F7);
  static Color activeChip({required bool dark}) =>
      dark ? const Color(0xFF20344D) : const Color(0xFFEBF3FF);
  static Color textThumbnail({required bool dark}) =>
      dark ? const Color(0xFF20344D) : const Color(0xFFECF2FF);

  static const double sendVisualSize = 32;
  static const double sendIconSize = 26;
  static const double sendProgressSize = 18;
  static const double sendProgressStroke = 2;
  static const Color sendBackgroundLight = Color(0xFFE9EFFA);
  static const Color sendBackgroundDark = Color(0xFF323D50);

  static Color sendBackground({required bool dark}) =>
      dark ? sendBackgroundDark : sendBackgroundLight;
}

/// Received message surfaces from 99chat's production theme and bubble helper.
class ChatBubbleTokens {
  ChatBubbleTokens._();

  static const Color incomingBorder = Color(0x14000000);
  static const double incomingBorderWidth = .5;
  static const double metadataHorizontalGap = 6;
  static const double metadataVerticalGap = 4;

  static Color incoming({required bool dark}) => AppTokens.surface(dark: dark);
}

/// Compact file and voice attachment rows in chat-history results.
class ChatHistoryFileTokens {
  ChatHistoryFileTokens._();

  static const double iconExtent = 44;
  static const double rowVerticalPadding = 2;
  static const double titleFontSize = 16;
  static const double timeFontSize = 13;
  static const double dividerHeight = 1;
  static const double progressExtent = 18;
  static const double progressStroke = 2;
}

/// Production 99chat mobile conversation and composer geometry.
class ChatComposerTokens {
  ChatComposerTokens._();

  static const Color backgroundLight = Color(0xFFF4F5F7);
  static const Color dividerLight = Color(0xFFEAEAEA);
  static const double inputHeight = 36;
  static const double verticalPadding = 5;
  static const double horizontalPadding = 16;
  static const double actionGap = 10;
  static const double iconSize = 26;
  static const double radius = 8;
  static const double dividerWidth = .5;
  static const double fontSize = 16;
  static const double lineHeight = 1.3;
  static const double textHorizontalPadding = 12;
  static const double textVerticalPadding = 8;
  static const double sendHeight = 30;
  static const double sendHorizontalPadding = 14;
  static const double sendFontSize = 14;
  static const double selectionOpacity = .22;

  static Color cursor({required bool dark}) =>
      dark ? AppTokens.onAccent : AppTokens.accent;

  static Color background({required bool dark}) =>
      dark ? AppTokens.backgroundDark : backgroundLight;
  static Color surface({required bool dark}) =>
      dark ? AppTokens.backgroundDark : AppTokens.surfaceLight;
  // DefTheme uses surfaceAltLight, rather than the demo's chatInputFillLight.
  static Color inputFill({required bool dark}) =>
      dark ? AppTokens.surfaceDark : AppTokens.surfaceAltLight;
  static Color divider({required bool dark}) =>
      dark ? AppTokens.borderDark : dividerLight;
}

/// Right-edge chat scroll hints, with the requested blue surface in both themes.
class ChatScrollHintTokens {
  ChatScrollHintTokens._();

  static const Color background = Color(0xFF1296F6);
  static const Color foreground = AppTokens.onAccent;
  static const Color shadow = Color(0x24000000);
  static const double minHeight = 32;
  static const double radius = 22;
  static const double iconSize = 17;
  static const double horizontalPadding = AppTokens.s4;
  static const double verticalPadding = 7;
  static const double bottomGap = AppTokens.s4;
  static const double shadowOffset = 2;
  static const double shadowBlur = 8;
}

/// Six-digit transaction password setup and numeric input surfaces.
class TradePasswordTokens {
  TradePasswordTokens._();

  static const double contentMaxWidth = 480;
  static const double logoSize = 80;
  static const double logoRadius = 16;
  static const double headingFontSize = 20;
  static const double helperFontSize = 14;
  static const double securityFontSize = 12;
  static const double digitFontSize = 24;
  static const double cellMaxSize = 48;
  static const double cellGap = 6;
  static const double dotSize = 9;
  static const double keyMinHeight = 48;
  static const double keyMaxHeight = 56;
  static const double keyHeightScreenRatio = 0.064;
  static const double deleteIconSize = 24;
  static const double securityIconSize = 20;
  static const Duration inputAnimation = Duration(milliseconds: 120);
}

/// 99chat fund surfaces, using the app's actual supported currencies.
class FundTokens {
  FundTokens._();

  // Geometry and art colors ported from 99chat d7c3c65.
  static const double referenceDesktopWidth = 720;
  static const double previewSidePaddingRatio = .08;
  static const double previewTopGapRatio = .026;
  static const double previewBottomGapRatio = .035;
  static const double previewMobileWidthRatio = .91;
  static const double previewDesktopWidthRatio = .55;
  static const double previewAspectRatio = 5 / 7;
  static const double previewCloseSizeMin = 46;
  static const double previewCloseSizeMax = 64;
  static const double previewCloseSizeRatio = .105;
  static const double previewCloseGapRatio = .04;
  static const double previewRadiusRatio = .055;
  static const double previewCoinSizeRatio = .28;
  static const double previewCoinBottomRatio = .06;
  static const double previewTypeTopRatio = .16;
  static const double previewTypeFontRatio = .04;
  static const double previewGreetingFontRatio = .083;
  static const double previewBlessingFontRatio = .027;
  static const double previewBlurSigma = 14;
  static const double previewMaskOpacity = .4;
  static const Duration openingDuration = Duration(milliseconds: 1500);
  static const Duration splitDuration = Duration(milliseconds: 300);
  static const Duration introDuration = Duration(milliseconds: 460);
  static const double luckyHeaderExtraHeight = 64;
  static const double detailTitleFont = 16;
  static const double recordAmountFont = 17;
  static const double recordTimeFont = 12;
  static const double progressFont = 13;
  static const double referenceDesignWidth = 750;
  static const double referenceDesignHeight = 1624;
  static const double normalHeaderHeightRatio = .18;
  static const double normalDesktopHeaderHeightRatio = .21;
  static const double transferStatusGlyphSize = 34;
  static const double transferTopGap = 58;
  static const double transferIconGap = 44;
  static const double transferSectionGap = 22;
  static const double transferMetaGap = 38;
  static const double transferMetaLabelWidth = 94;
  static const double coinLogoSize = 24;
  static const Color luckyHeader = Color(0xFFD9584D);
  static const Color goldEdge = Color(0xFFE8C58B);
  static const Color luckySurfaceDark = Color(0xFF191919);
  static const Color progressLight = Color(0xFFF7F7F7);
  static const Color progressDark = Color(0xFF202020);
  static const Color previewGold = Color(0xFFFFE8A0);
  static const Color previewError = Color(0xFFFFE6A8);
  static const Color previewTextShadow = Color(0x995B1200);
  static const Color coinShadow = Color(0x29000000);
  static const Color coinHoleShadow = Color(0x478A470E);
  static const Color coinGradientTop = Color(0xFFFFE79B);
  static const Color coinGradientMiddle = Color(0xFFF4B63C);
  static const Color coinGradientBottom = Color(0xFFC97918);
  static const Color coinBorder = Color(0xFFFFF0AD);
  static const Color coinLabel = Color(0xFF8A240C);
  static const Color coinHole = Color(0xFF8E4510);
  static const Color transferFilled = Color(0xFF12C85A);
  static const Color transferBlue = Color(0xFF2399E5);
  static const double referenceLoadingSize = 78;
  static const double referenceLoadingRadius = 18;
  static const Color referenceLoadingBackground = Color(0xAA000000);
  static const Color referenceMask = Color(0xFF000000);
  static const double referenceAmountGap = 30;
  static const double referenceEmptyGap = 48;
  static const double referenceRecordDividerIndent = 76;
  static const double referenceRecordGap = 5;
  static const double referenceStackWidth = 300;
  static const double referenceCoinLabelGap = 7;
  static const double referenceTransferMetaTopGap = 18;
  static const double memberAvatarSize = 42;
  static const double memberTitleFontSize = 16;
  static const double memberToolbarTitleFontSize = 17;
  static const double memberBackIconSize = 22;
  static const double memberSearchHeight = 44;
  static const double memberSearchFontSize = 15;
  static const double memberSearchRadius = 10;
  static const double memberSearchIconSize = 18;
  static const double memberPaginationThreshold = 250;
  static const double memberLoadingHeight = 48;

  static const double contentMaxWidth = 480;
  static const double detailMaxWidth = 680;
  static const double detailAmountFontSize = 48;
  static const double packetAmountFontSize = 56;
  static const double detailAmountLineHeight = 1.15;
  static const double iconSize = 28;
  static const double paymentSheetMaxWidth = 480;
  static const double chatAvatarSize = 40;
  static const double cardFooterDividerWidth = .5;
  static const double recordAvatarSize = 44;
  static const double detailSenderAvatarSize = 28;
  static const double detailUnitFontSize = 16;
  static const double transferStatusIconSize = 48;
  static const double detailGreetingFontSize = 20;
  static const double detailHeaderCurveHeight = 24;
  static const double detailStatusFontSize = 14;
  static const Duration openAnimationDuration = Duration(milliseconds: 350);
  static const Color coverScrim = Color(0x99000000);
  static const Color transparent = Color(0x00000000);
  static const double spinnerSize = 20;
  static const double spinnerStroke = 2;
  static const int memberPageSize = 50;
  static const Duration searchDebounce = Duration(milliseconds: 300);

  static Color amountGold({required bool dark}) =>
      dark ? const Color(0xFFE6C58B) : const Color(0xFFB08A4A);
}
