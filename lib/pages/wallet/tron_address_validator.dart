import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// TRON Base58Check address validation (mainnet `T...` / prefix `0x41`).
class TronAddressValidator {
  TronAddressValidator._();

  static const String _alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  static final RegExp _formatRegExp =
      RegExp(r'^T[1-9A-HJ-NP-Za-km-z]{33}$');

  static bool isValid(String value) {
    final trimmed = value.trim();
    if (!_formatRegExp.hasMatch(trimmed)) return false;
    final decoded = _base58Decode(trimmed);
    if (decoded == null || decoded.length != 25 || decoded[0] != 0x41) {
      return false;
    }
    final payload = decoded.sublist(0, 21);
    final checksum = decoded.sublist(21, 25);
    final hash = sha256.convert(sha256.convert(payload).bytes).bytes;
    for (var i = 0; i < 4; i++) {
      if (checksum[i] != hash[i]) return false;
    }
    return true;
  }

  static Uint8List? _base58Decode(String input) {
    var value = BigInt.zero;
    for (var i = 0; i < input.length; i++) {
      final digit = _alphabet.indexOf(input[i]);
      if (digit < 0) return null;
      value = value * BigInt.from(58) + BigInt.from(digit);
    }
    var bytes = _bigIntToBytes(value);
    var leadingZeros = 0;
    for (var i = 0; i < input.length && input[i] == '1'; i++) {
      leadingZeros++;
    }
    if (leadingZeros > 0) {
      bytes = Uint8List.fromList([
        ...List<int>.filled(leadingZeros, 0),
        ...bytes,
      ]);
    }
    return bytes;
  }

  static Uint8List _bigIntToBytes(BigInt value) {
    if (value == BigInt.zero) return Uint8List(0);
    final hex = value.toRadixString(16);
    final padded = hex.length.isOdd ? '0$hex' : hex;
    final bytes = Uint8List(padded.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
