import '../../pages/contacts/scanning/contact_qr_result.dart';
import '../../pages/wallet/tron_address_validator.dart';
import '../../widgets/qr_scanner/content/qr_content.dart';

enum RecognizedImageKind { friend, group, url, tron, text }

class RecognizedImageValue {
  const RecognizedImageValue(this.value, this.kind, {this.contact});
  final String value;
  final RecognizedImageKind kind;
  final Map<String, String>? contact;
}

/// Only checksummed addresses are accepted; OCR never repairs wallet characters.
List<RecognizedImageValue> parseImageRecognition(
    Iterable<String> codes, String text) {
  final values = <String, RecognizedImageValue>{};
  void add(RecognizedImageValue item) =>
      values.putIfAbsent(item.value, () => item);
  final address =
      RegExp(r'(?<![A-Za-z0-9])T[1-9A-HJ-NP-Za-km-z]{33}(?![A-Za-z0-9])');
  void addresses(String input) {
    for (final match in address.allMatches(input)) {
      final value = match.group(0)!;
      if (TronAddressValidator.isValid(value)) {
        add(RecognizedImageValue(value, RecognizedImageKind.tron));
      }
    }
  }

  for (final raw in codes) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    final contact = parseContactQrResult(value);
    if (contact?['groupID'] != null || contact?['userID'] != null) {
      add(RecognizedImageValue(
          value,
          contact!['groupID'] != null
              ? RecognizedImageKind.group
              : RecognizedImageKind.friend,
          contact: contact));
    } else if (TronAddressValidator.isValid(value)) {
      add(RecognizedImageValue(value, RecognizedImageKind.tron));
    } else {
      final content = QrContent.parse(value);
      add(RecognizedImageValue(
          value,
          content.url != null
              ? RecognizedImageKind.url
              : RecognizedImageKind.text));
      addresses(value);
    }
  }
  addresses(text);
  // Addresses often wrap across lines; checksum validation rejects false joins.
  addresses(text.replaceAll(RegExp(r'\s+'), ''));
  return values.values.toList(growable: false);
}
