import 'package:flutter/painting.dart';

/// Layout measurements from all six supplied dice animations.
abstract final class DiceStickerLayout {
  static const sourceSize = Size.square(512);

  // Every settled image fits x=110..402, y=199..499. Only the panel preview
  // removes its empty stage; chat messages retain the original square canvas.
  static const previewViewport = Rect.fromLTRB(104, 196, 408, 504);
}
