import 'package:openim_common/openim_common.dart';

/// Geometry for reviewing recorded speech without moving the underlying draft.
abstract final class VoiceTextPreviewTokens {
  static const height = 360.0;
  static const largeTextHeight = 440.0;
  static const compactHeight = 300.0;
  static const scrollFallbackHeight = 200.0;
  static const largeTextScrollFallbackHeight = 280.0;
  static const compactContentHeight = 152.0;
  static const maxWidth = 560.0;
  static const radius = AppTokens.s7;
  static const inset = AppTokens.s6;
  static const actionHeight = 48.0;
  static const closeSize = 44.0;
  static const spinnerRadius = 12.0;
  static const bodyLineHeight = 1.5;
  static const largeTextThreshold = 1.3;
  static const stackedActionWidth = 360.0;
  static const keyboardAnimation = Duration(milliseconds: 180);
}
