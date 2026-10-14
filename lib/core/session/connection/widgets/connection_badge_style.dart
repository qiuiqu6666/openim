import 'package:flutter/material.dart';

/// Reference artwork proportions, scaled for the 56 dp conversation toolbar.
abstract final class ConnectionBadgeStyle {
  static const height = 26.0;
  static const horizontalInset = 9.0;
  static const iconSize = 14.0;
  static const iconGap = 7.0;
  static const labelSize = 11.0;
  // Lowercase x-height is shorter than numerals; balance the visible glyphs.
  static const unitSize = 13.0;
  static const textOffsetY = 1.0;
  static ConnectionBadgePalette palette(int? ms, bool dark) {
    if (ms == null) {
      return dark
          ? const ConnectionBadgePalette(Color(0xFFC0CBD8), Color(0xFF71869C),
              Color(0xFF9BADBE), Color(0xFF26313F), Color(0xFF2D3948))
          : const ConnectionBadgePalette(Color(0xFF3E556E), Color(0xFF617B93),
              Color(0xFF94A7B8), Color(0xFFEDF2F7), Color(0xFFEAF0F5));
    }
    if (ms < 200) {
      return dark
          ? const ConnectionBadgePalette(Color(0xFF5CE3AB), Color(0xFF00BD64),
              Color(0xFF43E99B), Color(0xFF153C30), Color(0xFF194335))
          : const ConnectionBadgePalette(Color(0xFF00AA61), Color(0xFF00BE62),
              Color(0xFF31DB89), Color(0xFFE2FCF1), Color(0xFFDCFCEE));
    }
    if (ms < 500) {
      return dark
          ? const ConnectionBadgePalette(Color(0xFFFFC44A), Color(0xFFFFAC00),
              Color(0xFFFFD05C), Color(0xFF3B3019), Color(0xFF44381C))
          : const ConnectionBadgePalette(Color(0xFFDF8E00), Color(0xFFFFAD00),
              Color(0xFFFFC933), Color(0xFFFFF9E7), Color(0xFFFFF6DE));
    }
    return dark
        ? const ConnectionBadgePalette(Color(0xFFFF7D8B), Color(0xFFFF2948),
            Color(0xFFFF8491), Color(0xFF431F2B), Color(0xFF4C2432))
        : const ConnectionBadgePalette(Color(0xFFD71932), Color(0xFFFF2544),
            Color(0xFFFF7885), Color(0xFFFFEBEF), Color(0xFFFFE7EC));
  }
}

class ConnectionBadgePalette {
  const ConnectionBadgePalette(this.text, this.signalTop, this.signalBottom,
      this.backgroundTop, this.backgroundBottom);

  final Color text, signalTop, signalBottom, backgroundTop, backgroundBottom;
}
