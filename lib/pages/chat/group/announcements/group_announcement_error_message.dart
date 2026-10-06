import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

/// SDK error details contain native/server stacks, so only show known messages.
String groupAnnouncementPublishErrorMessage(Object error) {
  if (error is TimeoutException) {
    return 'groupAnnouncementPublishTimeout'.tr;
  }
  if (error is PlatformException) {
    final code = int.tryParse(error.code);
    if (code == SDKErrorCode.networkWaitTimeoutError) {
      return 'groupAnnouncementPublishTimeout'.tr;
    }
    if (code == SDKErrorCode.networkRequestError) {
      final message = (error.message ?? '').toLowerCase();
      if (message.contains('deadline exceeded') ||
          message.contains('timed out') ||
          message.contains('timeout')) {
        return 'groupAnnouncementPublishTimeout'.tr;
      }
      return StrRes.networkError;
    }
    if (code == SDKErrorCode.insufficientPermissions) {
      return StrRes.groupAcPermissionTips;
    }
    if (const {
      SDKErrorCode.groupNotExis,
      SDKErrorCode.userIsNotInGroup,
      SDKErrorCode.groupDisbanded,
    }.contains(code)) {
      return error.code.tr;
    }
  }
  return 'groupAnnouncementPublishFailed'.tr;
}
