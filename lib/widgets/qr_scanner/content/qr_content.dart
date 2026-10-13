import 'dart:convert';

enum QrContentKind { url, text, wifi, contact, unknown }

/// Interprets already-decoded text only. It never executes QR instructions.
class QrContent {
  const QrContent(this.raw, this.kind,
      {this.url, this.ssid, this.password, this.vcard});
  final String raw;
  final QrContentKind kind;
  final Uri? url;
  final String? ssid, password, vcard;

  static QrContent parse(String raw) {
    final text = raw.trim();
    final uri = Uri.tryParse(text);
    if (uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !RegExp(r'[\x00-\x20\x7f\u202a-\u202e\u2066-\u2069]').hasMatch(text)) {
      return QrContent(raw, QrContentKind.url, url: uri);
    }
    if (text.startsWith('WIFI:')) {
      final fields = _fields(text.substring(5));
      if (fields['S']?.isNotEmpty == true &&
          const ['WPA', 'WEP', 'nopass', 'SAE', '']
              .contains(fields['T'] ?? '')) {
        return QrContent(raw, QrContentKind.wifi,
            ssid: fields['S'], password: fields['P']);
      }
      return QrContent(raw, QrContentKind.unknown);
    }
    if (text.startsWith('BEGIN:VCARD') && text.endsWith('END:VCARD')) {
      return QrContent(raw, QrContentKind.contact, vcard: text);
    }
    if (text.startsWith('MECARD:')) {
      final fields = _fields(text.substring(7));
      if (fields['N']?.isNotEmpty == true) {
        String escape(String value) => value
            .replaceAll('\\', '\\\\')
            .replaceAll('\r', '')
            .replaceAll('\n', '\\n')
            .replaceAll(';', '\\;')
            .replaceAll(',', '\\,');
        final card = [
          'BEGIN:VCARD',
          'VERSION:3.0',
          'FN:${escape(fields['N']!)}',
          if (fields['TEL'] != null) 'TEL:${escape(fields['TEL']!)}',
          if (fields['EMAIL'] != null) 'EMAIL:${escape(fields['EMAIL']!)}',
          'END:VCARD'
        ].join('\r\n');
        return QrContent(raw, QrContentKind.contact, vcard: card);
      }
    }
    try {
      jsonDecode(text);
      return QrContent(raw, QrContentKind.unknown);
    } on FormatException {/* Ordinary text remains copyable. */}
    final unknown = uri?.hasScheme == true ||
        RegExp(r'^[A-Za-z0-9_-]+:').hasMatch(text) ||
        text.startsWith('{') ||
        text.startsWith('[');
    return QrContent(raw, unknown ? QrContentKind.unknown : QrContentKind.text);
  }
}

Map<String, String> _fields(String source) {
  final result = <String, String>{};
  final parts = <String>[];
  var part = StringBuffer(), escaped = false;
  for (final rune in source.runes) {
    final c = String.fromCharCode(rune);
    if (escaped) {
      part.write(c);
      escaped = false;
    } else if (c == '\\') {
      escaped = true;
    } else if (c == ';') {
      parts.add(part.toString());
      part = StringBuffer();
    } else {
      part.write(c);
    }
  }
  if (escaped) part.write('\\');
  parts.add(part.toString());
  for (final value in parts) {
    final colon = value.indexOf(':');
    if (colon > 0) {
      result.putIfAbsent(
          value.substring(0, colon), () => value.substring(colon + 1));
    }
  }
  return result;
}
