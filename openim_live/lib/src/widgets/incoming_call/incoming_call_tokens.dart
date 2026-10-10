import 'package:flutter/material.dart';

import '../call_surface/call_full_screen_surface.dart';

/// Geometry from 99chat's LiveKitCallPage, in logical pixels (not ScreenUtil).
abstract final class IncomingCallTokens {
  static const avatarSize = 110.0;
  static const nameGap = 20.0;
  static const sideInset = 16.0;
  static const minimizeLeft = 12.0;
  static const minimizeTop = 52.0;
  static const minimizePadding = 12.0;
  static const minimizeIconSize = 20.0;
  static const actionBottom = 50.0;
  static const actionIconSize = 60.0;
  static const actionWidth = 100.0;
  static const actionGap = 10.0;
  static const enterDuration = Duration(milliseconds: 180);
  static const audioBackdropDelay = Duration(milliseconds: 430);
  static const videoBackdropDelay = Duration(milliseconds: 630);
  static final backdropScrim =
      CallSurfaceTokens.background.withValues(alpha: .9);
  static const nameStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: CallSurfaceTokens.foreground,
  );
  static const hintStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: CallSurfaceTokens.foreground,
  );
  static const actionStyle = TextStyle(
    fontSize: 12,
    height: 1.25,
    fontWeight: FontWeight.w400,
    color: CallSurfaceTokens.foreground,
  );
}
