import 'dart:convert';

/// The roll is part of the message, so both sides and retries keep one result.
class DiceMessageData {
  DiceMessageData({required this.value}) {
    RangeError.checkValueInInterval(value, 1, 6, 'value');
  }

  static const customType = 906;
  static const protocolVersion = 1;
  final int value;

  static DiceMessageData? tryParse(String? data) {
    if (data == null || data.isEmpty) return null;
    try {
      final envelope = jsonDecode(data);
      if (envelope is! Map ||
          envelope['customType'] is! int ||
          envelope['customType'] != customType) {
        return null;
      }
      final payload = envelope['data'];
      if (payload is! Map ||
          payload['version'] is! int ||
          payload['version'] != protocolVersion) {
        return null;
      }
      final value = payload['value'];
      if (value is! int || value < 1 || value > 6) return null;
      return DiceMessageData(value: value);
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'customType': customType,
        'data': {'version': protocolVersion, 'value': value},
      };

  String encode() => jsonEncode(toJson());
}
