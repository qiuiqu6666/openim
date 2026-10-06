import 'dart:convert';

enum OfficialAccountRole { message, pay }

/// The two read-only notification roles supplied by the OpenIM user profile.
class OfficialAccount {
  const OfficialAccount({required this.userID, required this.role});

  static const messageUserID = '99Message';
  static const payUserID = '99Pay';
  static const assistantUserID = 'assistant';

  final String userID;
  final OfficialAccountRole role;

  bool get isPay => role == OfficialAccountRole.pay;

  String get displayName => isPay ? payUserID : messageUserID;

  String get description => isPay ? '支付通知' : '公告和基础消息';

  static Map<dynamic, dynamic>? _extension(String? ex) {
    if (ex == null || ex.trim().isEmpty) return null;
    try {
      final value = jsonDecode(ex);
      return value is Map ? value : null;
    } on FormatException {
      return null;
    }
  }

  static bool isOfficialExtension(String? ex) =>
      _extension(ex)?['accountType'] == 'official';

  /// A verification badge follows stable official IDs or identity metadata.
  static bool hasVerifiedIdentity({String? userID, String? ex}) {
    final id = userID?.trim() ?? '';
    return id.isNotEmpty &&
        (id == messageUserID ||
            id == payUserID ||
            id == assistantUserID ||
            isOfficialExtension(ex));
  }

  static OfficialAccount? from({String? userID, String? ex}) {
    final id = userID?.trim() ?? '';
    if (id.isEmpty) return null;
    // The server's stable IDs also work while SDK profile data is unavailable.
    if (id == messageUserID) {
      return OfficialAccount(userID: id, role: OfficialAccountRole.message);
    }
    if (id == payUserID) {
      return OfficialAccount(userID: id, role: OfficialAccountRole.pay);
    }
    final extension = _extension(ex);
    if (extension?['accountType'] != 'official') return null;
    final role = switch (extension?['officialRole']) {
      'message' => OfficialAccountRole.message,
      'pay' => OfficialAccountRole.pay,
      _ => null,
    };
    return role == null ? null : OfficialAccount(userID: id, role: role);
  }
}
