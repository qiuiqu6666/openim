import 'package:flutter/material.dart';

/// Source coordinates from the supplied ecosystem artwork.
class MineEcosystemArtwork extends StatelessWidget {
  const MineEcosystemArtwork({super.key, required this.index});
  final int index;
  static const asset = 'assets/images/profile_ecosystem_cards.png';
  static const windows = [
    Rect.fromLTWH(73, 386, 445, 349),
    Rect.fromLTWH(550, 384, 433, 350),
    Rect.fromLTWH(1014, 384, 431, 350),
    Rect.fromLTWH(1479, 384, 441, 350),
  ];
  @override
  Widget build(BuildContext context) {
    final window = windows[index];
    return ExcludeSemantics(
        child: Stack(fit: StackFit.expand, children: [
      FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: window.width,
            height: window.height,
            child: ClipRect(
                child: Stack(children: [
              Positioned(
                  left: -window.left,
                  top: -window.top,
                  width: 1983,
                  height: 793,
                  child:
                      Image.asset(asset, filterQuality: FilterQuality.medium)),
            ])),
          )),
    ]));
  }
}
