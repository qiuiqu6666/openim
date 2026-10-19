import 'dart:convert';

/// One SDK custom message is one complete model input, regardless of upload time.
class AiImageTurn {
  const AiImageTurn(
      {required this.turnID,
      required this.text,
      required this.images,
      this.generateImage = false});
  static const description = 'assistantTurn';
  final String turnID;
  final String text;
  final bool generateImage;
  final List<({String url, String name})> images;

  String encode() => jsonEncode({
        'version': 1,
        'turnID': turnID,
        'text': text,
        if (generateImage) 'intent': 'generate_image',
        'images': [
          for (final image in images) {'url': image.url, 'name': image.name}
        ],
      });

  static bool supported(String? ex, {bool generateImage = false}) {
    try {
      final data = jsonDecode(ex ?? '');
      return data is Map &&
          data['assistantTurnVersion'] == 1 &&
          (!generateImage || data['assistantImageEditVersion'] == 1);
    } on FormatException {
      return false;
    }
  }

  static AiImageTurn? parse(String? raw) {
    try {
      final data = jsonDecode(raw ?? '');
      if (data is! Map ||
          data['version'] != 1 ||
          data['turnID'] is! String ||
          data['text'] is! String ||
          data['images'] is! List) {
        return null;
      }
      final id = data['turnID'] as String;
      if (data['intent'] != null &&
          data['intent'] != '' &&
          data['intent'] != 'generate_image') {
        return null;
      }
      final text = data['text'] as String;
      if (id.length < 16 ||
          id.length > 128 ||
          text.trim().isEmpty ||
          text.runes.length > 8000) {
        return null;
      }
      final items = data['images'] as List;
      if (items.isEmpty || items.length > 3) return null;
      final images = <({String url, String name})>[];
      for (final item in items) {
        if (item is! Map || item['url'] is! String) return null;
        final uri = Uri.tryParse(item['url'] as String);
        if (uri == null ||
            !{'https', 'http'}.contains(uri.scheme) ||
            uri.host.isEmpty) {
          return null;
        }
        images.add((
          url: item['url'] as String,
          name: item['name'] is String ? item['name'] as String : ''
        ));
      }
      return AiImageTurn(
          turnID: data['turnID'] as String,
          text: data['text'] as String,
          generateImage: data['intent'] == 'generate_image',
          images: images);
    } on FormatException {
      return null;
    }
  }
}
