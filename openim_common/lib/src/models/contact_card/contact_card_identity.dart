import 'dart:convert';

/// A display snapshot is bound to the native SDK target, never a routing ID.
Map<String, dynamic> contactCardIdentityFields(String userID, String? account) {
  final publicAccount = account?.trim() ?? '';
  if (userID.trim().isEmpty || publicAccount.isEmpty) return {};
  return {
    'contactCard': {'userID': userID, 'account': publicAccount},
  };
}

/// Ignore unbound, mismatched and malformed extensions from historical cards.
String? contactCardAccount(String userID, String? ex) {
  if (userID.trim().isEmpty || ex == null || ex.isEmpty) return null;
  try {
    final decoded = jsonDecode(ex);
    if (decoded is! Map) return null;
    final identity = decoded['contactCard'];
    if (identity is! Map || identity['userID'] != userID) return null;
    final account = identity['account'];
    if (account is! String || account.trim().isEmpty) return null;
    return account.trim();
  } on FormatException {
    return null;
  }
}

/// Only original numeric legacy IDs may be displayed without a profile lookup.
String? legacyCardAccount(String userID) =>
    RegExp(r'^[0-9]+$').stringMatch(userID) == userID ? userID : null;
