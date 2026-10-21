import 'package:flutter/material.dart';

/// Displays only the planet from the supplied artwork, without its labels.
class MineEcosystemIcon extends StatelessWidget {
  const MineEcosystemIcon({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 400,
                height: 330,
                child: Stack(children: [
                  Positioned(
                    left: -210,
                    top: -215,
                    width: 2172,
                    height: 724,
                    child: Image.asset(
                      'assets/images/profile_ecosystem_planet.png',
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
