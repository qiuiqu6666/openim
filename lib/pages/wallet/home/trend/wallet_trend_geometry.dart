import 'package:flutter/material.dart';

import '../../data/wallet_trend_data.dart';

/// Shared geometry for painting and hit testing. Timestamps define horizontal
/// positions; tied events get a small ordered separation within the time gap.
class WalletTrendGeometry {
  WalletTrendGeometry(List<WalletTrendPoint> points, Size size,
      {bool evenlySpaced = false}) {
    if (points.isEmpty) return;
    final values = points.map((p) => p.cents).whereType<BigInt>().toList();
    final min =
        values.isEmpty ? BigInt.zero : values.reduce((a, b) => a < b ? a : b);
    final max =
        values.isEmpty ? BigInt.zero : values.reduce((a, b) => a > b ? a : b);
    final range = max - min;
    final times = <double>[];
    var minGap = double.infinity;
    for (var i = 1; i < points.length; i++) {
      final gap = points[i].createdAt - points[i - 1].createdAt;
      if (gap > 0 && gap < minGap) minGap = gap.toDouble();
    }
    var duplicate = 0;
    final step = minGap.isFinite ? minGap / (points.length + 1) : 1.0;
    for (var i = 0; i < points.length; i++) {
      duplicate = i > 0 && points[i].createdAt == points[i - 1].createdAt
          ? duplicate + 1
          : 0;
      times.add((points[i].createdAt - points.first.createdAt).toDouble() +
          duplicate * step);
    }
    final span = times.last - times.first;
    for (var i = 0; i < points.length; i++) {
      final x = evenlySpaced && points.length > 1
          ? i / (points.length - 1) * size.width
          : points.length == 1 || span == 0
              ? size.width / 2
              : times[i] / span * size.width;
      xs.add(x);
      final cents = points[i].cents;
      offsets.add(cents == null
          ? null
          : Offset(
              x,
              range == BigInt.zero
                  ? size.height / 2
                  : size.height *
                      (1 - (cents - min).toDouble() / range.toDouble())));
    }
  }

  final List<double> xs = [];
  final List<Offset?> offsets = [];

  int nearest(double x) {
    var result = 0;
    for (var i = 1; i < xs.length; i++) {
      if ((xs[i] - x).abs() < (xs[result] - x).abs()) result = i;
    }
    return result;
  }

  /// Cubic controls stay inside the endpoints' rectangle: smooth joins with
  /// horizontal tangents, no overshoot or invented peaks. Nulls break paths.
  List<Path> get paths {
    final result = <Path>[];
    Path? path;
    Offset? previous;
    for (final point in offsets) {
      if (point == null) {
        previous = null;
        path = null;
        continue;
      }
      if (previous == null) {
        path = Path()..moveTo(point.dx, point.dy);
        result.add(path);
      } else {
        final mid = (previous.dx + point.dx) / 2;
        path!.cubicTo(mid, previous.dy, mid, point.dy, point.dx, point.dy);
      }
      previous = point;
    }
    return result;
  }
}
