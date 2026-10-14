import 'package:openim_common/openim_common.dart';

import 'legacy_server_snapshot.dart';

/// The original hash stays stable; only the migrated group's prefix changes.
class LegacyGroupIdentity {
  static final _oldID = RegExp(r'^lg_[0-9a-f]{32}$');

  static String canonical(String id, {String? server}) =>
      _usesMigratedIDs(server ?? Config.imApiUrl) && _oldID.hasMatch(id)
          ? '@$id'
          : id;

  static bool _usesMigratedIDs(String server) {
    if (LegacyServerSnapshot.allowedServer(server)) return true;
    // Config migrated the built-in endpoint to this domain. Identity aliases
    // follow that deployment; destructive cleanup keeps its separate gate.
    final uri = Uri.tryParse(server);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == '99imapi.99chat.vip' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        (uri.path.isEmpty || uri.path == '/') &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }
}
