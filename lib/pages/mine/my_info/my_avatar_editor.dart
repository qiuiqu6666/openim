import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';

/// Shares the existing picker, crop, upload and profile update flow.
abstract final class MyAvatarEditor {
  static void open(IMController imLogic) {
    final avatarUrl = imLogic.userInfo.value.faceURL;
    final userID = imLogic.userInfo.value.userID ?? '';
    bool isActive() =>
        !imLogic.isClosed &&
        userID.isNotEmpty &&
        imLogic.userInfo.value.userID == userID;
    IMViews.openPhotoSheet(
        avatarUrl: avatarUrl,
        isActive: isActive,
        onData: (path, url) async {
          if (url == null) return;
          try {
            await LoadingView.singleton.wrap(
              asyncFunction: () =>
                  Apis.updateUserInfo(userID: userID, faceURL: url),
            );
            if (isActive()) {
              imLogic.userInfo.update((value) => value?.faceURL = url);
            }
          } catch (_) {
            if (isActive()) IMViews.showToast(StrRes.saveFailed);
          }
        },
        quality: 15);
  }
}
