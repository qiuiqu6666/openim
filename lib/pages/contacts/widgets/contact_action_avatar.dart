import 'package:flutter/material.dart';

/// Source windows in the supplied artwork, preserving the original rendering.
enum ContactActionArtwork {
  newFriend(139, 132, 392),
  groupNotice(609, 132, 394),
  myGroups(1077, 132, 392),
  channel(1548, 132, 394);

  const ContactActionArtwork(this.left, this.top, this.diameter);
  final double left;
  final double top;
  final double diameter;
}

/// One shared asset is decoded by Flutter's image cache for all four entries.
/// The row supplies the accessible label; the artwork is decorative.
class ContactActionAvatar extends StatelessWidget {
  const ContactActionAvatar({
    super.key,
    required this.artwork,
    required this.size,
  });

  final ContactActionArtwork artwork;
  final double size;
  static const asset = 'assets/images/contact_actions_reference.png';
  static const sourceSize = Size(2081, 755);

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: ClipOval(
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox.square(
                dimension: artwork.diameter,
                child: Stack(children: [
                  Positioned(
                    left: -artwork.left,
                    top: -artwork.top,
                    width: sourceSize.width,
                    height: sourceSize.height,
                    child:
                        Image.asset(asset, filterQuality: FilterQuality.medium),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
