import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Original 99chat assets and proportions from lib/src/profile.dart.
class MineEcosystemArtwork extends StatelessWidget {
  const MineEcosystemArtwork(
      {super.key, required this.index, required this.title});
  final int index;
  final String title;
  static const assets = [
    'assets/images/profile_eco_ai_99chat.webp',
    'assets/images/profile_eco_shop_99chat.webp',
    'assets/images/profile_eco_wallet_99chat.webp',
    'assets/images/profile_eco_community_99chat.webp',
  ];
  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final arrow = width * 0.16;
        return Stack(fit: StackFit.expand, children: [
          Transform.scale(
              scale: 1.34,
              child: Image.asset(assets[index],
                  package: 'openim_common',
                  fit: BoxFit.cover,
                  alignment: Alignment.center)),
          Positioned(
              left: width * 0.06,
              right: width * 0.06,
              bottom: width * 0.10,
              child: Row(children: [
                Container(
                    width: arrow,
                    height: arrow,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTokens.onAccent.withValues(alpha: 0.35),
                        border: Border.all(
                            color: AppTokens.onAccent.withValues(alpha: 0.75),
                            width: arrow * 0.06)),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: AppTokens.onAccent, size: arrow * 0.68)),
                SizedBox(width: width * 0.03),
                Expanded(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(title,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                                color: AppTokens.onAccent,
                                fontSize: width * 0.11,
                                fontWeight: FontWeight.w700,
                                height: 1.1)))),
              ])),
        ]);
      }));
}
