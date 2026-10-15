import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

class MessageSendSessionChanged implements Exception {
  const MessageSendSessionChanged();
}

/// Freeze the SDK owner and service credentials before a send-related await.
class MessageSendSession {
  MessageSendSession.capture()
      : accountID = OpenIM.iMManager.userID,
        _imToken = DataSp.imToken,
        _chatToken = DataSp.chatToken,
        _imApi = Config.imApiUrl,
        _chatApi = Config.appAuthUrl;

  final String accountID, _imApi, _chatApi;
  final String? _imToken, _chatToken;

  /// Ownership for presenting results, even after the same account changes node.
  /// This does not authorize starting new work on a different SDK connection.
  bool get identityCurrent =>
      OpenIM.iMManager.userID == accountID &&
      DataSp.imToken == _imToken &&
      DataSp.chatToken == _chatToken;

  bool get current =>
      identityCurrent &&
      Config.imApiUrl == _imApi &&
      Config.appAuthUrl == _chatApi;

  void check() {
    if (!current) throw const MessageSendSessionChanged();
  }
}
