import 'customer_service_config.dart';

class CustomerServiceAttachment {
  const CustomerServiceAttachment({
    required this.fileType,
    required this.dataUrl,
    required this.thumbUrl,
    required this.fileName,
    this.width = 0,
    this.height = 0,
  });

  final String fileType, dataUrl, thumbUrl, fileName;
  final int width, height;

  factory CustomerServiceAttachment.fromJson(Map<String, dynamic> json,
      {CustomerServiceConfig config = const CustomerServiceConfig()}) {
    String first(List<String> keys) {
      for (final key in keys) {
        final text = json[key]?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    final rawType = json['file_type'] ?? json['fileType'];
    final type = switch (rawType?.toString().trim().toLowerCase()) {
      '0' || 'image' => 'image',
      '1' || 'audio' => 'audio',
      '2' || 'video' => 'video',
      final String value when value.isNotEmpty => value,
      _ => 'file',
    };
    final name = first(['file_name', 'filename', 'name']);
    final extension = first(['extension']);
    return CustomerServiceAttachment(
      fileType: type,
      dataUrl: config.resolveMediaUrl(
          first(['data_url', 'dataUrl', 'file_url', 'fileUrl', 'url'])),
      thumbUrl: config.resolveMediaUrl(first(['thumb_url', 'thumbUrl'])),
      fileName: name.isNotEmpty
          ? name
          : (extension.isEmpty ? 'file' : 'file.$extension'),
      width: _int(json['width']),
      height: _int(json['height']),
    );
  }
}

int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
