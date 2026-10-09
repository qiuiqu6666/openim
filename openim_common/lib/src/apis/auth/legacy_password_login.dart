import 'legacy_password_envelope.dart';

/// The original password stays in memory; the wire contains only a pinned-key
/// RSA-OAEP-SHA256 envelope, after an explicit legacy challenge.
class LegacyPasswordLogin {
  LegacyPasswordLogin._();

  static Future<dynamic> submit({
    required Map<String, dynamic> request,
    required Uri endpoint,
    required Future<dynamic> Function(Map<String, dynamic>) post,
    bool Function()? isCurrent,
  }) async {
    final normal = Map<String, dynamic>.from(request)
      ..remove('passwordPlaintext');
    try {
      return await post(normal);
    } catch (error) {
      if (error is! (int, String?) || error.$1 != 20084) rethrow;
      final plaintext = request['passwordPlaintext'];
      if (plaintext is! String || plaintext.isEmpty) rethrow;
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Login attempt is no longer current');
      }
      return post({
        ...normal,
        'passwordPlaintext':
            LegacyPasswordEnvelope.encrypt(plaintext, endpoint),
      });
    }
  }
}
