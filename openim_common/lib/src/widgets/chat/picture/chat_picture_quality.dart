import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Decode the pixels used by a fit-width bubble, including the cropped area.
/// A square decode bound would reduce a 1:20 image to a very narrow strip.
class ChatPictureQuality {
  ChatPictureQuality._();

  static const maxDecodedPixels = 4 * 1024 * 1024;
  static const maxDecodedSide = 8192;

  static Size sourceSize(PictureElem? picture) {
    for (final info in [
      picture?.sourcePicture,
      picture?.bigPicture,
      picture?.snapshotPicture,
    ]) {
      if ((info?.width ?? 0) > 0 && (info?.height ?? 0) > 0) {
        return Size(info!.width!.toDouble(), info.height!.toDouble());
      }
    }
    return const Size(1, 1);
  }

  static Size decodeSize({
    required Size source,
    required double displayWidth,
    required double devicePixelRatio,
  }) {
    final dpr = devicePixelRatio.isFinite && devicePixelRatio > 0
        ? devicePixelRatio
        : 1.0;
    final width = math.min(source.width, (displayWidth * dpr).ceilToDouble());
    final height = width * source.height / source.width;
    final scale = math.min(
      1.0,
      math.min(
        math.sqrt(maxDecodedPixels / (width * height)),
        maxDecodedSide / math.max(width, height),
      ),
    );
    return Size(math.max(1, (width * scale).floor()).toDouble(),
        math.max(1, (height * scale).floor()).toDouble());
  }

  /// Keep original/signed URLs intact; a square thumbnail transform can erase
  /// the short-axis detail before Flutter gets a chance to decode the image.
  static String? croppedSource(PictureElem? picture, Size decodeSize) {
    final big = picture?.bigPicture;
    if (_url(big?.url) != null &&
        (big?.width ?? 0) >= decodeSize.width &&
        (big?.height ?? 0) >= decodeSize.height) {
      return big!.url;
    }
    return _url(picture?.sourcePicture?.url) ??
        _url(big?.url) ??
        _url(picture?.snapshotPicture?.url);
  }

  static String? _url(String? value) =>
      value != null && value.trim().isNotEmpty ? value : null;
}
