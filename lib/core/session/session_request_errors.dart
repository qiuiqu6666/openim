import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Recognize failures belonging to the current profile request.
/// HttpUtil reports the expiry event once for its captured request token.
bool handleSessionAuthFailure(Object error,
    {required String account, required String? token}) {
  if (account != OpenIM.iMManager.userID ||
      token == null ||
      token.isEmpty ||
      token != DataSp.chatToken ||
      error is! (int, String?)) {
    return false;
  }
  return ApiErrorMessages.isSessionError(error.$1);
}
