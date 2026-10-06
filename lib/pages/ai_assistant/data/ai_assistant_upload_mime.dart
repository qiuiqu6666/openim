import 'dart:typed_data';

class AiAssistantUploadMime {
  AiAssistantUploadMime._();

  static const int maxBytes = 20 * 1024 * 1024;
  static const int maxFileCount = 3;
  static const int maxContentChars = 8000;

  static const String xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const String xlsMime = 'application/vnd.ms-excel';

  static const Set<String> allowedMimes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'application/pdf',
    xlsxMime,
    xlsMime,
    'text/csv',
    'video/mp4',
    'video/quicktime',
    'video/webm',
  };

  static const Set<String> allowedImageMimes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  };

  static const Set<String> allowedSpreadsheetMimes = <String>{
    xlsxMime,
    xlsMime,
    'text/csv',
  };

  static const Set<String> allowedVideoMimes = <String>{
    'video/mp4',
    'video/quicktime',
    'video/webm',
  };

  static String? fromName(String fileName) {
    final trimmed = fileName.trim();
    final dot = trimmed.lastIndexOf('.');
    if (dot < 0 || dot == trimmed.length - 1) {
      return null;
    }
    switch (trimmed.substring(dot + 1).toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'xlsx':
        return xlsxMime;
      case 'xls':
        return xlsMime;
      case 'csv':
        return 'text/csv';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      default:
        return null;
    }
  }

  static bool matchesMime(String fileName, String? mimeType) {
    final expected = fromName(fileName);
    if (expected == null) {
      return false;
    }
    final actual = (mimeType ?? '').trim().toLowerCase();
    if (actual.isEmpty || actual == 'application/octet-stream') {
      return true;
    }
    if (expected == 'image/jpeg') {
      return actual == 'image/jpeg' || actual == 'image/jpg';
    }
    if (expected == 'text/csv') {
      return actual == 'text/csv' ||
          actual == 'text/plain' ||
          actual == 'application/csv';
    }
    return actual == expected;
  }

  static bool isAllowedImage(String fileName, String? mimeType) {
    final expected = fromName(fileName);
    if (expected == null || !allowedImageMimes.contains(expected)) {
      return false;
    }
    return matchesMime(fileName, mimeType);
  }

  static bool isSpreadsheet(String fileName, String? mimeType) {
    final expected = fromName(fileName);
    if (expected == null || !allowedSpreadsheetMimes.contains(expected)) {
      return false;
    }
    return matchesMime(fileName, mimeType);
  }

  static bool isAllowedVideo(String fileName, String? mimeType) {
    final expected = fromName(fileName);
    if (expected == null || !allowedVideoMimes.contains(expected)) {
      return false;
    }
    return matchesMime(fileName, mimeType);
  }

  static bool isChatAttachment(String fileName, String? mimeType) {
    return isAllowedImage(fileName, mimeType) ||
        isSpreadsheet(fileName, mimeType) ||
        isAllowedVideo(fileName, mimeType);
  }

  static bool isPdf(String fileName, String? mimeType) {
    final expected = fromName(fileName);
    final actual = (mimeType ?? '').trim().toLowerCase();
    return expected == 'application/pdf' || actual == 'application/pdf';
  }

  static String? sniffMime(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'application/pdf';
    }
    return null;
  }

  static bool isImageBytes(Uint8List bytes) {
    final mime = sniffMime(bytes);
    return mime != null && allowedImageMimes.contains(mime);
  }

  static String ensureFileName(String fileName, String? mimeType) {
    final name = fileName.trim().isEmpty ? 'file' : fileName.trim();
    if (fromName(name) != null) {
      return name;
    }
    switch ((mimeType ?? '').trim().toLowerCase()) {
      case 'image/jpeg':
      case 'image/jpg':
        return '$name.jpg';
      case 'image/png':
        return '$name.png';
      case 'image/webp':
        return '$name.webp';
      case 'image/gif':
        return '$name.gif';
      case 'application/pdf':
        return '$name.pdf';
      case xlsxMime:
        return '$name.xlsx';
      case xlsMime:
        return '$name.xls';
      case 'text/csv':
      case 'application/csv':
        return '$name.csv';
      case 'video/mp4':
        return '$name.mp4';
      case 'video/quicktime':
        return '$name.mov';
      case 'video/webm':
        return '$name.webm';
      default:
        return name;
    }
  }
}
