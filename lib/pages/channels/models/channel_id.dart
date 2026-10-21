import 'dart:math';

/// Case-sensitive OpenIM group ID, with all three character classes present.
String generateChannelID() {
  final random = Random.secure();
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  while (true) {
    final id = List.generate(12, (_) => alphabet[random.nextInt(alphabet.length)]).join();
    if (RegExp('[A-Z]').hasMatch(id) &&
        RegExp('[a-z]').hasMatch(id) &&
        RegExp('[0-9]').hasMatch(id)) {
      return id;
    }
  }
}
