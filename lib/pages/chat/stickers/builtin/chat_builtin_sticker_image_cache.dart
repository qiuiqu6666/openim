import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Reuses the uploaded, bundled PNG for the URL-based message's first frame.
/// Flutter owns eviction; no local resource path enters the message payload.
Future<void> warmBuiltinStickerImage({
  required String url,
  required Uint8List bytes,
  bool Function()? isCurrent,
}) async {
  final provider = ExtendedNetworkImageProvider(url, cache: true);
  final key = await provider.obtainKey(ImageConfiguration.empty);
  if (isCurrent?.call() == false) return;
  final cache = PaintingBinding.instance.imageCache;
  if (cache.containsKey(key)) return;

  // Builtin artwork is static PNG. Keep only its first frame in the same cache
  // consumed by ChatImageSticker, rather than a separate outgoing-image store.
  final codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame;
  try {
    frame = await codec.getNextFrame();
  } finally {
    codec.dispose();
  }
  final info = ImageInfo(image: frame.image);
  var inserted = false;
  try {
    if (isCurrent?.call() == false) return;
    cache.putIfAbsent(key, () {
      inserted = true;
      return OneFrameImageStreamCompleter(SynchronousFuture(info));
    });
  } finally {
    // Another loader may have populated this URL while decoding was pending.
    if (!inserted) info.dispose();
  }
}
