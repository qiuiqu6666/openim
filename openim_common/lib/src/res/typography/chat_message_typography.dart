import 'package:flutter/material.dart';

import '../app_tokens.dart';
import 'platform_text_fonts.dart';

/// Matches 99chat's MessageBubbleTextColor.messageBodyBaseStyle. Message text
/// must not inherit Material body spacing or an unrelated page's font family.
TextStyle chatMessageTextStyle(BuildContext context) => TextStyle(
      inherit: false,
      fontFamily: PlatformTextFonts.familyOf(context),
      fontFamilyFallback: PlatformTextFonts.fallbackOf(context),
      fontSize: ChatBubbleTokens.textFontSize,
      fontWeight: FontWeight.w400,
      height: ChatBubbleTokens.textLineHeight,
      textBaseline: TextBaseline.alphabetic,
      color: ChatBubbleTokens.bodyText(
          dark: Theme.of(context).brightness == Brightness.dark),
    );
