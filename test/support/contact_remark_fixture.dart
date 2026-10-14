import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class ContactRemarkFixture extends GetxController
    implements ContactRemarkSource {
  final owner = OpenIM.iMManager.userID;
  final remarks = <String, String>{}.obs;

  @override
  bool get isCurrentSession => owner == OpenIM.iMManager.userID;

  @override
  String? remarkFor(String? userID) {
    final value = remarks[userID]?.trim();
    return isCurrentSession && value?.isNotEmpty == true ? value : null;
  }

  @override
  Iterable<String> matchingRemarkUserIDs(String keyword) {
    if (!isCurrentSession || keyword.trim().isEmpty) return [];
    return remarks.entries
        .where((entry) =>
            entry.value.toLowerCase().contains(keyword.trim().toLowerCase()))
        .map((entry) => entry.key)
        .toList();
  }
}
