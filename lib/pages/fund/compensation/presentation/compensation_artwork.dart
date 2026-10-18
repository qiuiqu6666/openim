import 'package:flutter/material.dart';
import 'compensation_tokens.dart';

/// Atlas coordinates are expressed in the original designer's 1871 × 841 canvas.
/// The bitmap stays decorative; values and controls are real Flutter widgets.
class CompensationArtwork extends StatelessWidget {
  const CompensationArtwork(this.region, {super.key, this.original = false})
      : stateAtlas = false;
  const CompensationArtwork.states(this.region,
      {super.key, this.original = false})
      : stateAtlas = true;
  final bool stateAtlas;
  static const stateAsset = 'assets/images/compensation_state_atlas.png';
  static const stateSource =
      'assets/images/compensation_state_atlas_source.png';
  static const stateHeader = Rect.fromLTWH(0, 0, 1222, 345);
  static const stateClosed = Rect.fromLTWH(65, 374, 330, 286);
  static const stateEnded = Rect.fromLTWH(830, 374, 325, 286);
  static const statePool = Rect.fromLTWH(25, 662, 1155, 180);
  static const stateGift = Rect.fromLTWH(890, 1070, 325, 210);
  final Rect region;
  final bool original;
  static const asset = 'assets/images/compensation_detail_atlas.png';
  static const source = 'assets/images/compensation_detail_atlas_source.png';
  static const header = Rect.fromLTWH(0, 0, 965, 395);
  static const envelope = Rect.fromLTWH(965, 0, 540, 400);
  // The card and 99 seal share this axis; the coins extend farther right.
  static const envelopeCenterX = 230.0;
  static const claimed = Rect.fromLTWH(1060, 606, 250, 102);
  static const ended = Rect.fromLTWH(1580, 606, 250, 102);
  static const unclaimed = Rect.fromLTWH(1310, 606, 270, 102);
  static const action = Rect.fromLTWH(28, 592, 580, 120);
  static const coins = Rect.fromLTWH(1350, 710, 160, 125);
  static const pool = Rect.fromLTWH(25, 399, 970, 190);
  static const gift = Rect.fromLTWH(1495, 416, 365, 184);

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: AspectRatio(
            aspectRatio: region.width / region.height,
            child: LayoutBuilder(builder: (context, box) {
              final scale = box.maxWidth / region.width;
              return ClipRect(
                  child: Stack(children: [
                Positioned(
                  left: -region.left * scale,
                  top: -region.top * scale,
                  width: (stateAtlas ? 1222 : 1871) * scale,
                  height: (stateAtlas ? 1287 : 841) * scale,
                  child: Image.asset(
                      stateAtlas
                          ? (original ? stateSource : stateAsset)
                          : (original ? source : asset),
                      fit: BoxFit.fill,
                      excludeFromSemantics: true),
                )
              ]));
            })),
      );
}

class CompensationAction extends StatelessWidget {
  const CompensationAction(
      {super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(
            child: Opacity(
                opacity: onPressed == null ? .5 : 1,
                child: FittedBox(
                    fit: BoxFit.fill,
                    child: const SizedBox(
                        width: 580,
                        height: 120,
                        child:
                            CompensationArtwork(CompensationArtwork.action))))),
        SizedBox(
            width: double.infinity,
            child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: CompensationTokens.posterText,
                    disabledForegroundColor: CompensationTokens.posterText,
                    minimumSize: const Size(
                        CompensationTokens.touch, CompensationTokens.touch),
                    padding: const EdgeInsets.symmetric(
                        horizontal: CompensationTokens.inset,
                        vertical: CompensationTokens.space)),
                onPressed: onPressed,
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: CompensationTokens.posterTitle,
                        fontWeight: FontWeight.w800)))),
      ]);
}
