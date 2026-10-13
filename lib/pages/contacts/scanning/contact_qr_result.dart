import '../../login/desktop_authorization/data/desktop_authorization_service.dart';
import 'package:openim_common/openim_common.dart';

/// Keeps the existing friend result fields; group invitations return groupID.
Map<String, String>? parseContactQrResult(String value) {
  final requestId = parseDesktopLoginQr(value);
  if (requestId != null) return {'desktopLoginRequestId': requestId};
  final groupID = parseGroupQrLink(value);
  if (groupID != null) return {'groupID': groupID};
  try {
    return parseFriendInvite(value);
  } on FormatException {
    return null;
  }
}
