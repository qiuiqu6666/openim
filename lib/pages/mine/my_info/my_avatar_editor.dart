import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';

/// Shares the existing picker, crop, upload and profile update flow.
abstract final class MyAvatarEditor {
  static void open(IMController imLogic) {
    final avatarUrl = imLogic.userInfo.value.faceURL;
    IMViews.openPhotoSheet(
        items: IMUtils.isUrlValid(avatarUrl)
            ? [
                SheetItem(
                  label: StrRes.viewAvatar,
                  onTap: () => IMUtils.previewUrlPicture(
                    [MediaSource(thumbnail: avatarUrl!, url: avatarUrl)],
                    showSaveButton: true,
                  ),
                ),
              ]
            : const [],
        onData: (path, url) async {
          if (url == null) return;
          try {
            await LoadingView.singleton.wrap(
              asyncFunction: () => Apis.updateUserInfo(
                  userID: OpenIM.iMManager.userID, faceURL: url),
            );
            if (!imLogic.isClosed) {
              imLogic.userInfo.update((value) => value?.faceURL = url);
            }
          } catch (_) {
            IMViews.showToast(StrRes.saveFailed);
          }
        },
        quality: 15);
  }
}
