/// The final P0 contract only fixes the two capability field names. Unknown
/// quota fields remain read-only metadata until their wire names are documented.
class FavoriteQuota {
  const FavoriteQuota(
      {required this.supportsFavorites,
      required this.supportsPrepareSend,
      this.limits = const {}});
  final bool supportsFavorites;
  final bool supportsPrepareSend;
  final Map<String, Object?> limits;
  bool get available => supportsFavorites && supportsPrepareSend;

  factory FavoriteQuota.fromJson(Map<String, dynamic> json) {
    if (json['supportsFavorites'] is! bool ||
        json['supportsPrepareSend'] is! bool) {
      throw const FormatException('Invalid favorite capabilities');
    }
    return FavoriteQuota(
        supportsFavorites: json['supportsFavorites'] as bool,
        supportsPrepareSend: json['supportsPrepareSend'] as bool,
        limits: Map.unmodifiable(Map<String, Object?>.from(json)
          ..remove('supportsFavorites')
          ..remove('supportsPrepareSend')));
  }
}
