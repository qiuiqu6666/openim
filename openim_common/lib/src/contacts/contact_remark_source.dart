import 'package:get/get.dart';

/// Read-only access to the account's existing contact directory.
abstract interface class ContactRemarkSource {
  bool get isCurrentSession;

  String? remarkFor(String? userID);

  Iterable<String> matchingRemarkUserIDs(String keyword);

  static ContactRemarkSource? get current {
    if (!Get.isRegistered<ContactRemarkSource>()) return null;
    final source = Get.find<ContactRemarkSource>();
    return source.isCurrentSession ? source : null;
  }

  static String displayName(String? userID,
      {String? nickname, String? fallbackRemark}) {
    final source = current;
    return nameFromValues(userID,
        nickname: nickname,
        remark: source == null ? fallbackRemark : source.remarkFor(userID));
  }

  static String nameFromValues(String? userID,
      {String? nickname, String? remark}) {
    for (final value in [remark, nickname, userID]) {
      final name = value?.trim() ?? '';
      if (name.isNotEmpty) return name;
    }
    return '';
  }
}
