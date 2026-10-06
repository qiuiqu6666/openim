import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:image_picker/image_picker.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

import '../../../widgets/auth/auth_copy.dart';

class RegistrationAvatar {
  const RegistrationAvatar({
    required this.path,
    required this.name,
    required this.bytes,
  });

  final String path;
  final String name;
  final Uint8List bytes;
}

/// Selects a local preview, then uses the existing authenticated SDK upload.
class RegistrationAvatarService {
  const RegistrationAvatarService();

  Future<RegistrationAvatar?> pick() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (photo == null) return null;
    if (await photo.length() > 10 * 1024 * 1024) {
      IMViews.showToast(authText('头像不能超过 10 MB', 'Avatar must be under 10 MB'));
      return null;
    }
    return RegistrationAvatar(
      path: photo.path,
      name: photo.name,
      bytes: await photo.readAsBytes(),
    );
  }

  Future<String?> upload(
    RegistrationAvatar avatar, {
    required String userID,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    final result = await OpenIM.iMManager.uploadFile(
      id: const Uuid().v4(),
      filePath: avatar.path,
      fileName: avatar.name,
    );
    if (!isCurrent()) return null;
    final data = result is String ? jsonDecode(result) : result;
    final url = data is Map ? data['url'] : null;
    if (url is! String || !IMUtils.isUrlValid(url)) {
      throw const FormatException('Invalid registration avatar URL');
    }
    await Apis.updateUserInfo(
      userID: userID,
      faceURL: url,
      showErrorToast: false,
      isCurrent: isCurrent,
    );
    return isCurrent() ? url : null;
  }
}
