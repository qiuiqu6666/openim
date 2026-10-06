// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:flutter/services.dart';

/// 自定义数字键盘：按键音 + 触觉反馈。
class KeypadFeedback {
  KeypadFeedback._();

  static void digitTap() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();
  }

  static void deleteTap() {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.heavyImpact();
  }
}
