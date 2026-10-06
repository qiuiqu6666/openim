import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

import 'moments_privacy_selections.dart';
export 'moments_privacy_selections.dart';

typedef MomentsPrivacySnapshotReader = Future<String?> Function(String key);
typedef MomentsPrivacySnapshotWriter = Future<bool> Function(
    String key, String value);

/// Small, account/server-owned confirmed records. All read-modify-write work
/// shares a key lock, including work from separate repository instances.
class MomentsPrivacySelectionStore {
  MomentsPrivacySelectionStore(
      {MomentsPrivacySnapshotReader? readSnapshot,
      MomentsPrivacySnapshotWriter? writeSnapshot})
      : _readSnapshot = readSnapshot,
        _writeSnapshot = writeSnapshot;

  final MomentsPrivacySnapshotReader? _readSnapshot;
  final MomentsPrivacySnapshotWriter? _writeSnapshot;
  static final _locks = <String, Lock>{};

  static String canonicalBaseUrl(String baseUrl) {
    final raw = baseUrl.trim();
    if (raw.isEmpty) throw ArgumentError('Business origin is required');
    final uri = Uri.tryParse(raw);
    // Injected environments may be opaque names. Keep them distinct and never
    // manufacture a production endpoint for a missing or non-URL origin.
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return raw.replaceFirst(RegExp(r'/+$'), '');
    }
    if (uri.userInfo.isNotEmpty) {
      throw ArgumentError('Business origins cannot include credentials');
    }
    final scheme = uri.scheme.toLowerCase();
    final defaultPort = scheme == 'https' ? 443 : 80;
    return Uri(
            scheme: scheme,
            host: uri.host.toLowerCase(),
            port: uri.port == defaultPort ? null : uri.port,
            path: uri.path.replaceFirst(RegExp(r'/+$'), ''),
            query: uri.hasQuery ? uri.query : null,
            fragment: uri.hasFragment ? uri.fragment : null)
        .toString();
  }

  static String storageKey(
      {required String ownerUserId, required String baseUrl}) {
    final owner = ownerUserId.trim();
    if (owner.isEmpty) throw ArgumentError.value(ownerUserId, 'ownerUserId');
    return 'moments:privacy-selections:v1:${jsonEncode([
          canonicalBaseUrl(baseUrl),
          owner
        ])}';
  }

  Future<MomentsPrivacySelections> load(
      {required String ownerUserId, required String baseUrl}) {
    final owner = ownerUserId.trim();
    final server = canonicalBaseUrl(baseUrl);
    final key = storageKey(ownerUserId: owner, baseUrl: server);
    return (_locks[key] ??= Lock())
        .synchronized(() => _read(key, owner, server));
  }

  Future<MomentsPrivacySelections> apply(
      {required String ownerUserId,
      required String baseUrl,
      required List<MomentsPrivacyChange> changes}) {
    final owner = ownerUserId.trim();
    final server = canonicalBaseUrl(baseUrl);
    final key = storageKey(ownerUserId: owner, baseUrl: server);
    final captured = List<MomentsPrivacyChange>.unmodifiable(changes);
    return (_locks[key] ??= Lock()).synchronized(() async {
      final previous = await _read(key, owner, server);
      if (captured.isEmpty) return previous;
      final updated = previous.apply(captured);
      final encoded = jsonEncode({
        'version': 1,
        'ownerUserId': owner,
        'baseUrl': server,
        'blockedViewerIds': updated.blockedViewerIds,
        'hiddenAuthorIds': updated.hiddenAuthorIds,
      });
      final success = _writeSnapshot != null
          ? await _writeSnapshot(key, encoded)
          : await (await SharedPreferences.getInstance())
              .setString(key, encoded);
      if (!success) {
        throw StateError('Could not persist confirmed privacy selections');
      }
      return updated;
    });
  }

  Future<MomentsPrivacySelections> _read(
      String key, String owner, String server) async {
    final raw = _readSnapshot != null
        ? await _readSnapshot(key)
        : (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return MomentsPrivacySelections.empty;
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['ownerUserId'] != owner ||
        decoded['baseUrl'] != server) {
      throw const FormatException('Invalid privacy selection snapshot');
    }
    List<String> ids(String field) {
      final values = decoded[field];
      if (values is! List || values.any((id) => id is! String)) {
        throw const FormatException('Invalid privacy selection IDs');
      }
      return values.cast<String>();
    }

    return MomentsPrivacySelections(
        blockedViewerIds: ids('blockedViewerIds'),
        hiddenAuthorIds: ids('hiddenAuthorIds'));
  }
}
