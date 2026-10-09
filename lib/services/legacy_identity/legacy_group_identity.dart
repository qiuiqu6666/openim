import 'package:openim_common/openim_common.dart';

import 'legacy_server_snapshot.dart';

/// The original hash stays stable; only the migrated group's prefix changes.
class LegacyGroupIdentity {
  static final _oldID = RegExp(r'^lg_[0-9a-f]{32}$');

  static String canonical(String id, {String? server}) =>
      LegacyServerSnapshot.allowedServer(server ?? Config.imApiUrl) &&
              _oldID.hasMatch(id)
          ? '@$id'
          : id;
}
