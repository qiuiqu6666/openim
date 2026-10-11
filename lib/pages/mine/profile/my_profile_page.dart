import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';
import '../../../services/moments_repository.dart';
import '../../moments/moments_page.dart';
import '../settings/openim_profile_service.dart';
import '../settings/pages/profile_info_page.dart';
import '../settings/settings_draft_store.dart';
import '../settings/settings_navigation.dart';

/// Route host for self mentions, avatars and cards. Reuses the editable profile
/// from Mine, with account-owned data instead of a message's group nickname.
class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  late final _controller = Get.find<IMController>();
  final _owner = (OpenIM.iMManager.userID, DataSp.imToken);
  late final _store = SettingsDraftStore();
  late final _service = OpenIMProfileService(_controller);
  late final Worker _profileUpdates;
  bool _momentsOpen = false;

  bool get _isCurrent =>
      !_controller.isClosed &&
      _owner.$1.isNotEmpty &&
      _owner == (OpenIM.iMManager.userID, DataSp.imToken) &&
      _controller.userInfo.value.userID == _owner.$1;

  @override
  void initState() {
    super.initState();
    _syncProfile(_controller.userInfo.value);
    _profileUpdates = ever(_controller.userInfo, _syncProfile);
  }

  void _syncProfile(UserFullInfo user) {
    if (!_isCurrent) return;
    _store.seedProfile(
      nickname: user.nickname ?? '',
      signature: OpenIMProfileService.signatureFromEx(user.ex),
    );
    _store.syncProfileSignature(OpenIMProfileService.signatureFromEx(user.ex));
  }

  Future<void> _openMoments() async {
    if (!mounted || !_isCurrent || _momentsOpen) return;
    _momentsOpen = true;
    final user = _controller.userInfo.value;
    try {
      await openSettingsPage<void>(
        context,
        MomentsPage(
          authorId: _owner.$1,
          profileUser: MomentUser(
            userId: _owner.$1,
            nickname: user.nickname ?? '',
            avatarUrl: user.faceURL ?? '',
          ),
        ),
        activityPage: 'moments',
      );
    } finally {
      _momentsOpen = false;
    }
  }

  @override
  void dispose() {
    _profileUpdates.dispose();
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final user = _controller.userInfo.value;
        if (!_isCurrent) return const SizedBox.shrink();
        return ProfileInfoPage(
          nickname: user.nickname ?? '',
          userId: _owner.$1,
          account: user.account?.trim() ?? '',
          avatarUrl: user.faceURL ?? '',
          phoneNumber: user.phoneNumber ?? '',
          gender: user.gender ?? 0,
          birth: user.birth ?? 0,
          store: _store,
          service: _service,
          onMomentsTap: _openMoments,
        );
      });
}
