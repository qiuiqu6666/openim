abstract interface class WalletTrendSource {
  Future<WalletTrendData> getTrend();
}

class WalletTrendData {
  const WalletTrendData({required this.points, this.currentCny});
  final List<WalletTrendPoint> points;
  final String? currentCny;

  factory WalletTrendData.fromJson(Map<String, dynamic> json) {
    final raw = json['points'];
    if (raw is! List || raw.length > 100) {
      throw const FormatException('Invalid trend points');
    }
    final points = raw.map((value) {
      if (value is! Map) throw const FormatException('Invalid trend point');
      final id = value['id'];
      final time = value['createdAt'];
      if (id is! String || time is! int) {
        throw const FormatException('Invalid trend identity');
      }
      return WalletTrendPoint(
        id: id,
        createdAt: time,
        totalCny: value['priceStatus'] == 'ready'
            ? validTrendMoney(value['totalCny'])
            : null,
      );
    }).toList(growable: false);
    return WalletTrendData(
        points: List.unmodifiable(points),
        currentCny: validTrendMoney(json['currentCny']));
  }
}

String? validTrendMoney(dynamic value) =>
    value is String && RegExp(r'^-?\d+\.\d{2}$').hasMatch(value) ? value : null;

class WalletTrendPoint {
  const WalletTrendPoint(
      {required this.id, required this.createdAt, required this.totalCny});
  final String id;
  final int createdAt;

  /// Null is a historical price gap, never zero.
  final String? totalCny;
  BigInt? get cents =>
      totalCny == null ? null : BigInt.parse(totalCny!.replaceAll('.', ''));
}
