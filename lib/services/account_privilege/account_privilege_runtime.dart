import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../core/session/current_user_profile_source.dart';
import 'account_privilege_store.dart';

export 'account_privilege_store.dart';

class AccountPrivilegeRuntime {
  static final source = CurrentUserProfileSource();
  static final store = AccountPrivilegeStore(
      session: () {
        final account = OpenIM.iMManager.userID;
        final token = DataSp.chatToken;
        if (account.isEmpty ||
            DataSp.userID != account ||
            token == null ||
            token.isEmpty) {
          return null;
        }
        return AccountPrivilegeSession(
            userID: account, chatToken: token, baseUrl: Config.appAuthUrl);
      },
      fetchProfile: (session) => source.fetch(session.userID, session.chatToken,
          baseUrl: session.baseUrl));
}
