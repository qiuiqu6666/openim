import 'package:flutter/material.dart';

/// Transparent planet artwork for both light and dark surfaces.
class MineEcosystemIcon extends StatelessWidget {
  const MineEcosystemIcon({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Image.asset(
          'assets/images/profile_ecosystem_planet_transparent.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      );
}
