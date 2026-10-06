import '../../data/wallet_trend_data.dart';

/// Presentation-only zero padding. Original API records are never modified.
class WalletTrendDisplayPoints {
  WalletTrendDisplayPoints(List<WalletTrendPoint> records) {
    final recent = records.length > slotCount
        ? records.sublist(records.length - slotCount)
        : records;
    paddingCount = slotCount - recent.length;
    points = List.unmodifiable([
      for (var i = 0; i < paddingCount; i++)
        WalletTrendPoint(
            id: 'display-padding-$i', createdAt: 0, totalCny: '0.00'),
      ...recent,
    ]);
  }

  static const slotCount = 40;
  late final int paddingCount;
  late final List<WalletTrendPoint> points;
}
