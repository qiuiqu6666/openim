/// Avatar addresses share the lifetime of the account-owned API runtime.
abstract final class LiveAvatarCache {
  static final _runtimes = Expando<Map<String, String>>();

  static String read(Object runtime, String scope) =>
      _runtimes[runtime]?[scope] ?? '';

  static void write(Object runtime, String scope, String url) {
    final entries = _runtimes[runtime] ??= <String, String>{};
    entries.remove(scope);
    if (entries.length >= 100) entries.remove(entries.keys.first);
    if (url.isNotEmpty) entries[scope] = url;
  }
}
