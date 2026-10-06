import 'dart:convert';

/// Keeps image dimensions in face messages without changing their SDK type.
class StickerImageData {
  const StickerImageData({required this.url, this.width, this.height});

  final String url;
  final int? width;
  final int? height;

  static StickerImageData? tryParse(String? data) {
    if (data == null || data.isEmpty) return null;
    Object? payload = data;
    try {
      payload = jsonDecode(data);
    } on FormatException {
      // Existing face messages contain the raw URL.
    }
    if (payload is Map && payload['data'] is Map) payload = payload['data'];
    final value = payload is Map ? payload['url'] : payload;
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return null;
    }
    final width = payload is Map ? _dimension(payload['width']) : null;
    final height = payload is Map ? _dimension(payload['height']) : null;
    return StickerImageData(
      url: value,
      width: width != null && height != null ? width : null,
      height: width != null && height != null ? height : null,
    );
  }

  static int? _dimension(Object? value) {
    if (value is! num || !value.isFinite || value <= 0) return null;
    final dimension = value.round();
    return dimension > 0 ? dimension : null;
  }

  String encode() {
    final validWidth = _dimension(width);
    final validHeight = _dimension(height);
    if (validWidth == null || validHeight == null) return url;
    return jsonEncode({
      'url': url,
      'width': validWidth,
      'height': validHeight,
    });
  }
}
