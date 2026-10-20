import 'package:flutter/widgets.dart';

/// Accelerating travel when revealing a referenced or searched message.
abstract final class ChatPositionMotion {
  static const duration = Duration(milliseconds: 420);
  static const curve = Curves.easeInCubic;
}
