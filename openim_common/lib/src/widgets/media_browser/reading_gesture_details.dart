import 'package:extended_image/extended_image.dart';
import 'package:flutter/widgets.dart';

/// Extend only pan limits. The image is still fitted against the full viewport.
class ReadingGestureDetails extends GestureDetails {
  ReadingGestureDetails(GestureDetails source, this.insets, this.extendEdges)
      : super(
            offset: source.offset,
            totalScale: source.totalScale,
            gestureDetails: source,
            actionType: source.actionType,
            userOffset: source.userOffset,
            initialAlignment: source.initialAlignment,
            slidePageOffset: source.slidePageOffset,
            rawDestinationRect: source.rawDestinationRect);
  final EdgeInsets insets;
  final bool extendEdges;

  @override
  Rect calculateFinalDestinationRect(Rect layoutRect, Rect destinationRect) {
    final bounds = extendEdges && (totalScale ?? 1) > 1
        ? insets.deflateRect(layoutRect)
        : layoutRect;
    return super.calculateFinalDestinationRect(bounds, destinationRect);
  }

  @override
  GestureDetails copy() =>
      ReadingGestureDetails(super.copy(), insets, extendEdges);
}
