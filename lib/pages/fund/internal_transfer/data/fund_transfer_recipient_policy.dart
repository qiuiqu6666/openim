import '../../../official_account/models/official_account.dart';

/// Internal transfers accept personal recipients, excluding official services.
/// Uses stable IDs and SDK identity metadata, never display names or remarks.
abstract final class FundTransferRecipientPolicy {
  static bool allowsUser({String? userID, String? ex}) {
    final id = userID?.trim() ?? '';
    return id.isNotEmpty &&
        !OfficialAccount.hasVerifiedIdentity(userID: id, ex: ex);
  }
}
