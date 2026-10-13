import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Media controls retain contrast independently of the thumbnail and app theme.
class ChatVideoPlayIndicator extends StatelessWidget {
  const ChatVideoPlayIndicator({super.key});

  static const double diameter = 36;
  static const double iconSize = 36;
  static const Color foreground = Color(0xFFFFFFFF);
  static const String _circlePlay = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round">
<circle cx="12" cy="12" r="10" fill="#000000" fill-opacity="0.4"/>
<path d="M9 9.003a1 1 0 0 1 1.517-.859l4.997 2.997a1 1 0 0 1 0 1.718l-4.997 2.997A1 1 0 0 1 9 14.996z"/>
</svg>
''';

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: SvgPicture.string(_circlePlay,
                width: iconSize,
                height: iconSize,
                theme: const SvgTheme(currentColor: foreground)),
          ),
        ),
      );
}
