import 'dart:convert';

/// Public group display metadata. It never grants business permissions.
enum GroupGameType {
  ordinary,
  sangong,
  markSixAgent,

  /// Public lottery results (gameType 3), separate from agent identity.
  markSix,
  sangongAgent;

  static GroupGameType fromEx(String? ex) {
    try {
      final metadata = jsonDecode(ex ?? '');
      if (metadata is! Map) return ordinary;
      final value = metadata['gameType'];
      if (value is! num) return ordinary;
      if (value == 1) return sangong;
      if (value == 2) return markSixAgent;
      if (value == 3) return markSix;
      if (value == 4) return sangongAgent;
    } catch (_) {
      // Unknown or malformed public metadata uses the ordinary group display.
    }
    return ordinary;
  }
}
