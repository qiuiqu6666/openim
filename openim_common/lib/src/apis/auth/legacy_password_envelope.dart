import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/random/fortuna_random.dart';

/// Pinned during deployment, never loaded or replaced through HTTP.
class LegacyPasswordEnvelope {
  LegacyPasswordEnvelope._();
  static const prefix = 'rsa-oaep-sha256-v1:';
  static const host = '129.226.192.93';
  static const _modulusHex =
      'ab050879c9d655aa55a207f468e8843fc9450fed8d857917e03e9e2cfd8eb79bf5299fde0314aa586cbf17744345d9bd040caa3a5aeefe737df5de1677729a9831c260f00875d017fcc314150d4930db3bd6efcaf4c85ea73a6c475538966519ad4b341e277a877c403d84f4a588fc58376c5d2eedec596ac7209bd0f9dba78c6a433db7556cf443a9a941b231889d21429e64b7b9271580ed5cf6304b89d920bfb7f9ceb8e5374b0d405ac084a379195dae619e64da7172dd27d1d073c435a8a7175bd4ed742d16fbecb53d29d3b959b1615cc8d25d082f0856a4ea5762d207a0ec8143bbed3ad8e72331bb4791efa55ccb97918053b7a3250b46d75402b9f3348970520e815d44d30c05b18e967fd81903134031debcdbf3e88c57e8e395cae16e39bd29959b146c7cf27bedef634949beece9d8740e892c92b155d3d1295b4e4423fb5614ee4d15c256c6777a58ec515f5fdcc5d4cff11f8fddd4b0c6f6850b0998171da7967633039d21de18eba181dc79c87ac8402c07092feab74848cb';

  static bool permits(Uri endpoint) =>
      {'http', 'https'}.contains(endpoint.scheme) &&
      endpoint.host == host &&
      endpoint.userInfo.isEmpty;

  static String encrypt(String plaintext, Uri endpoint) {
    if (!permits(endpoint)) {
      throw const FormatException('Unsupported legacy login server');
    }
    final source = Random.secure();
    final random = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(
          List<int>.generate(32, (_) => source.nextInt(256)))));
    final key =
        RSAPublicKey(BigInt.parse(_modulusHex, radix: 16), BigInt.from(65537));
    final cipher = OAEPEncoding.withSHA256(RSAEngine())
      ..init(true,
          ParametersWithRandom(PublicKeyParameter<RSAPublicKey>(key), random));
    final input = Uint8List.fromList(utf8.encode(plaintext));
    try {
      if (input.isEmpty || input.length > cipher.inputBlockSize) {
        throw const FormatException('Invalid legacy password length');
      }
      return prefix + base64Encode(cipher.process(input));
    } finally {
      input.fillRange(0, input.length, 0);
    }
  }
}
