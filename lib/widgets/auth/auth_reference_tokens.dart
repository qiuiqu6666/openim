import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;

/// Fixed authentication palette from reference-99chat/src/ui/app_tokens.dart.
/// Product surfaces continue to use the application's semantic theme tokens.
abstract final class AuthReferenceTokens {
  static const brand500 = AppTokens.accent;
  static const link = Color(0xFF176AC2);
  static const surface = AppTokens.surfaceLight;
  static const fieldFill = Color(0xFFF1F2F4);
  static const fieldBorder = Color(0xFFE2E6ED);
  static const hint = Color(0xFF626B7A);
  static const error = Color(0xFFB42318);
  static const ink900 = Color(0xFF0B1220);
  static const ink800 = Color(0xFF111827);
  static const ink400 = Color(0xFF6B7280);
  static const ink300 = Color(0xFF9CA3AF);
  static const ink150 = Color(0xFFE6E6E9);
  static const ink100 = Color(0xFFE5E7EB);
  static const ink600 = Color(0xFF374151);
  static const ink50 = Color(0xFFF3F4F6);
  static const brand50 = Color(0xFFEAF4FF);
  static const brand100 = Color(0xFFD7EBFF);
  static const divider = Color(0xFFEEF0F4);
  static const rLg = AppTokens.rLg;
  static const fieldGap = 20.0;
  // A reserved message row already supplies the space between field groups.
  static const feedbackFieldGap = 4.0;
  static const buttonGap = 24.0;
  static const fieldHeight = 52.0;
  static const fieldBorderWidth = 1.5;
  static const focusedFieldBorderWidth = 2.0;
  static const fieldContentPadding =
      EdgeInsets.symmetric(horizontal: 18, vertical: 14);
  static const compoundFieldContentPadding = EdgeInsets.fromLTRB(12, 14, 8, 14);
  static const inputFontSize = 16.0;
  static const labelGap = 8.0;
  static const messageGap = 4.0;
  static const messageHeight = 18.0;
  static const tapTarget = 48.0;
  static const toolbarGap = 4.0;
  static const toolbarIcon = 22.0;
  static const heroTopGap = 40.0;
  static const heroTabGap = 20.0;
  static const heroBottomGap = 20.0;
  static const tabSize = 20.0;
  static const tabUnderline = 3.0;
  static const formPadding = EdgeInsets.fromLTRB(28, 24, 28, 24);
  static const label =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink800);
  // Plain secondary authentication forms retain 99chat's original dimensions.
  static const formHeaderHorizontal = 24.0;
  static const formHeaderTop = 16.0;
  static const formHeaderBottom = 32.0;
  static const formHeaderBackGap = 20.0;
  static const formHeaderSubtitleGap = 6.0;
  static const formBackSize = 36.0;
  static const formBackRadius = 10.0;
  static const formBackIcon = 16.0;
  static const plainFormPadding = EdgeInsets.fromLTRB(28, 34, 28, 24);
  static const plainFormBottom = 24.0;
  static const keyboardScrollExtra = 120.0;
  static const bannerPadding = 14.0;
  static const bannerRadius = 12.0;
  static const bannerIcon = 20.0;
  static const bannerIconGap = 12.0;
  static const plainFieldLabelPadding = EdgeInsets.only(bottom: 12, left: 2);
  static const plainFormBannerGap = 24.0;
  static const plainFormButtonGap = 28.0;
  static const codeActionWidth = 100.0;
  static const formTitle = TextStyle(
      fontSize: 28, fontWeight: FontWeight.w700, color: ink900, height: 1.2);
  static const formSubtitle = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w400, color: ink400, height: 1.45);
  static const bannerText = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w400, color: ink600, height: 1.5);
  static const plainFieldLabel =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink800);
  static const plainFieldInput = TextStyle(
      fontSize: 18, fontWeight: FontWeight.w500, color: ink800, height: 1.2);
  static const plainFieldHint = TextStyle(
      fontSize: 18, fontWeight: FontWeight.w400, color: ink300, height: 1.2);
  static const codeAction =
      TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: brand500);
  static const plainFormButton = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: surface,
      height: 1.2,
      letterSpacing: 0);
  static const buttonShadow = [
    BoxShadow(color: Color(0x0A0B1220), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static const caption = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w400, color: ink400, height: 1.4);
  static const hero = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      height: 1.18);
  static const button =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white);
}
