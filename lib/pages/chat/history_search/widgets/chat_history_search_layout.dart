import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Matches 99chat's current form-factor policy without reacting to phone IME
/// height changes. Native phones use width; only web uses landscape as desktop.
bool chatHistorySearchIsDesktop(BuildContext context) {
  if (!kIsWeb &&
      const [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux]
          .contains(defaultTargetPlatform)) {
    return true;
  }
  final width = MediaQuery.widthOf(context);
  return width > 900 || (kIsWeb && width > MediaQuery.heightOf(context) * 1.1);
}
