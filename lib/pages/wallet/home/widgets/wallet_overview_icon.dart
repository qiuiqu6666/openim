import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../wallet_home_tokens.dart';

/// The reference overview's two matching document-outline icons.
class WalletOverviewIcon extends StatelessWidget {
  const WalletOverviewIcon.details({super.key}) : _svg = _details;
  const WalletOverviewIcon.history({super.key}) : _svg = _history;

  final String _svg;

  static const _details = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
  <rect x="4.5" y="2" width="15" height="20" rx="2"/>
  <path d="m7.5 11 3-3 3 2 3-4M7.5 17h9"/>
</svg>
''';

  static const _history = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
  <path d="M18 5V3.5A1.5 1.5 0 0 0 16.5 2h-12A1.5 1.5 0 0 0 3 3.5V17"/>
  <path d="M11 21H8a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v2M9 11h6"/>
  <circle cx="17.5" cy="17.5" r="4.5"/>
  <path d="M17.5 15v2.5H20"/>
</svg>
''';

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SvgPicture.string(
          _svg,
          width: WalletHomeTokens.icon,
          height: WalletHomeTokens.icon,
          colorFilter: ColorFilter.mode(
              IconTheme.of(context).color ??
                  Theme.of(context).colorScheme.onSurface,
              BlendMode.srcIn),
        ),
      );
}
