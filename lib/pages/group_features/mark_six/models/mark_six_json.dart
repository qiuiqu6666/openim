Map<String, dynamic> markSixMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> markSixRows(dynamic value) {
  final raw = value is Map ? value['items'] : value;
  return raw is List ? raw.whereType<Map>().map(markSixMap).toList() : [];
}
