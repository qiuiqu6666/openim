import 'package:flutter/animation.dart';
import 'package:openim_common/openim_common.dart';

abstract final class ChatMessageArrivalTokens {
  static const duration = Duration(milliseconds: 240);
  // Resume individual entrances only after live traffic has become quiet.
  static const quietPeriod = Duration(milliseconds: 600);
  static const curve = Curves.easeOutCubic;
  static const extentCurve = Curves.easeInOutCubic;
  static const outsideGap = AppTokens.s2;
  static const maxConcurrent = 4;
}
