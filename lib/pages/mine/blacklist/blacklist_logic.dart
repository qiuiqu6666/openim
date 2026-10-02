import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

class BlacklistLogic extends GetxController {
  final blacklist = <BlacklistInfo>[].obs;
  final loading = true.obs;
  final failed = false.obs;
  final removing = <String>{}.obs;
  bool _fetching = false;
  Future<void> loadBlacklist() async {
    if (_fetching) return;
    _fetching = true;
    loading.value = true;
    failed.value = false;
    try {
      final list = await OpenIM.iMManager.friendshipManager.getBlacklist();
      if (!isClosed) blacklist.assignAll(list);
    } catch (_) {
      if (!isClosed) failed.value = true;
    } finally {
      _fetching = false;
      if (!isClosed) loading.value = false;
    }
  }

  static String? blockedUserID(BlacklistInfo info) {
    for (final id in [info.blockUserID, info.userID]) {
      if (id != null && id.trim().isNotEmpty) return id;
    }
    return null;
  }

  Future<bool> remove(BlacklistInfo info) async {
    final id = blockedUserID(info);
    if (id == null) throw StateError('黑名单联系人缺少用户 ID，请重新加载后重试');
    if (!removing.add(id)) return false;
    try {
      await OpenIM.iMManager.friendshipManager.removeBlacklist(userID: id);
      if (!isClosed) blacklist.removeWhere((user) => blockedUserID(user) == id);
      return true;
    } finally {
      if (!isClosed) removing.remove(id);
    }
  }

  @override
  void onReady() {
    loadBlacklist();
    super.onReady();
  }
}
