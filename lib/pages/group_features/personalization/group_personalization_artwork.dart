import 'package:flutter/material.dart';

/// Original supplied artwork; source windows exclude labels and selection badges.
class GroupPersonalizationArtwork extends StatelessWidget {
  const GroupPersonalizationArtwork(
      {super.key, required this.iconKey, required this.size});
  final String iconKey;
  final double size;
  static const asset = 'assets/images/group_personalization_reference.png';
  static const windows = <String, Rect>{
    'robot': Rect.fromLTWH(74, 250, 166, 166),
    'heart': Rect.fromLTWH(326, 974, 74, 74),
    'crown': Rect.fromLTWH(441, 970, 80, 80),
    'game': Rect.fromLTWH(560, 973, 80, 80),
    'beer': Rect.fromLTWH(680, 970, 80, 80),
    'football': Rect.fromLTWH(800, 971, 80, 80),
    'rocket': Rect.fromLTWH(74, 1095, 80, 80),
    'clover': Rect.fromLTWH(196, 1094, 80, 80),
    'dog': Rect.fromLTWH(316, 1092, 80, 80),
    'diamond': Rect.fromLTWH(432, 1095, 80, 80),
    'ghost': Rect.fromLTWH(552, 1093, 80, 80),
    'star': Rect.fromLTWH(671, 1095, 80, 80),
    'flower': Rect.fromLTWH(790, 1092, 80, 80),
  };
  @override
  Widget build(BuildContext context) {
    final window = windows[iconKey];
    if (window == null) return SizedBox.square(dimension: size);
    return ExcludeSemantics(
        child: SizedBox.square(
            dimension: size,
            child: ClipRRect(
                borderRadius: BorderRadius.circular(size * .18),
                child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                        width: window.width,
                        height: window.height,
                        child: ClipRect(
                            child: Stack(children: [
                          Positioned(
                              left: -window.left,
                              top: -window.top,
                              width: 938,
                              height: 1676,
                              child: Image.asset(asset,
                                  filterQuality: FilterQuality.medium))
                        ])))))));
  }
}
