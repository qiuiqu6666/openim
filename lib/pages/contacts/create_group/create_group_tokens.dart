import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Geometry and colors from 99chat's mobile create-group form.
class CreateGroupTokens {
  const CreateGroupTokens._(this.dark);

  factory CreateGroupTokens.of(BuildContext context) =>
      CreateGroupTokens._(Theme.of(context).brightness == Brightness.dark);

  final bool dark;
  Color get background =>
      dark ? AppTokens.backgroundDark : const Color(0xFFF4F7FD);
  Color get surface => AppTokens.surface(dark: dark);
  Color get inset => dark ? AppTokens.surfaceAltDark : const Color(0xFFF3F6FB);
  Color get title => dark ? AppTokens.textPrimaryDark : const Color(0xFF192134);
  Color get secondary =>
      dark ? AppTokens.textSecondaryDark : const Color(0xFF8A95A8);
  Color get addBorder =>
      dark ? AppTokens.accent.withValues(alpha: .45) : const Color(0xFFB7D5FF);
  Color get accent => AppTokens.accent;

  static const cardPadding = 16.0;
  static const cardRadius = 20.0;
  static const cardGap = 12.0;
  static const sectionTitleSize = 16.0;
  static const toolbarTitleSize = 17.0;
  static const avatarSize = 58.0;
  static const subtitleGap = 6.0;
  static const subtitleSize = 12.0;
  static const avatarChevronGap = 8.0;
  static const nameGap = 10.0;
  static const nameInputPadding = 12.0;
  static const nameInputSize = 16.0;
  static const nameCountSize = 12.0;
  static const maxNameLength = 30;
  static const insetRadius = 12.0;
  static const memberAvatarSize = 44.0;
  static const memberItemWidth = 60.0;
  static const memberNameSize = 12.0;
  static const memberGap = 10.0;
  static const memberRunGap = 12.0;
  static const memberNameGap = 6.0;
  static const memberHeaderGap = 8.0;
  static const noticeGap = 18.0;
  static const policyPadding = 12.0;
  static const policyIconSize = 22.0;
  static const policyTextSize = 11.0;
  static const chevronSize = 24.0;
  static const addIconSize = 17.0;
  static const actionSize = 16.0;
  static const actionTarget = 48.0;
  static const progressSize = 18.0;
  static const defaultAvatarAsset =
      'lib/pages/contacts/create_group/assets/default_group_avatar.svg';
}
