import 'package:file_picker/file_picker.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

import '../settings_draft_store.dart';
import '../settings_navigation.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';
import 'change_phone_page.dart';
import 'edit_nickname_page.dart';
import 'edit_signature_page.dart';
import 'qr_profile_page.dart';

class ProfileInfoPage extends StatefulWidget {
  const ProfileInfoPage({
    super.key,
    required this.nickname,
    required this.userId,
    required this.avatarUrl,
    required this.store,
    this.account = '',
    this.phoneNumber = '',
    this.gender = 0,
    this.birth = 0,
    this.service = const StubSettingsService(),
    this.onMomentsTap,
  });

  final String nickname;
  /// SDK identity used in QR invitation links.
  final String userId;
  /// Public 99Chat account displayed and copied by the profile.
  final String account;
  final String avatarUrl;
  final String phoneNumber;
  final int gender;
  final int birth;
  final SettingsDraftStore store;
  final SettingsService service;
  final VoidCallback? onMomentsTap;

  @override
  State<ProfileInfoPage> createState() => _ProfileInfoPageState();
}

class _ProfileInfoPageState extends State<ProfileInfoPage> {
  bool _pickingAvatar = false;
  bool _savingProfile = false;
  late int _gender;
  late int _birth;

  @override
  void initState() {
    super.initState();
    _gender = widget.gender;
    _birth = widget.birth;
  }

  Future<void> _changeAvatar() async {
    if (_pickingAvatar) return;
    final desktop = SettingsResponsive.isDesktop(context);
    final source = await showSettingsActionSheet<String>(
      context,
      title: settingsText(context, zh: '更换头像', en: 'Change Avatar'),
      actions: [
        if (!desktop)
          SettingsAction(
              settingsText(context, zh: '拍照', en: 'Take Photo'), 'camera'),
        SettingsAction(
          settingsText(
            context,
            zh: desktop ? '从本地选择' : '从手机相册选择',
            en: desktop ? 'Choose from Files' : 'Choose from Photos',
          ),
          'photos',
        ),
        SettingsAction(
            settingsText(context, zh: '查看头像', en: 'View Avatar'), 'view'),
      ],
    );
    if (source == null || !mounted) return;
    if (source == 'view') {
      await _viewAvatar();
      return;
    }

    setState(() => _pickingAvatar = true);
    try {
      Uint8List? bytes;
      String? uploadPath;

      if (desktop && source == 'photos') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );
        final picked = (result == null || result.files.isEmpty)
            ? null
            : result.files.single;
        if (picked == null) return;
        bytes = picked.bytes;
        uploadPath = picked.path;
      } else {
        AssetEntity? asset;
        if (source == 'camera') {
          asset = await CameraPicker.pickFromCamera(
            context,
            pickerConfig: const CameraPickerConfig(
              enableRecording: false,
              enableAudio: false,
              enableScaledPreview: false,
            ),
          );
        } else {
          final assets = await AssetPicker.pickAssets(
            context,
            pickerConfig: AssetPickerConfig(
              maxAssets: 1,
              requestType: RequestType.image,
              sortPathsByModifiedDate: true,
              filterOptions: PMFilter.defaultValue(containsPathModified: true),
            ),
          );
          asset = (assets == null || assets.isEmpty) ? null : assets.first;
        }
        if (!mounted || asset == null) return;
        bytes = await asset.thumbnailDataWithSize(
          const ThumbnailSize(1200, 1200),
          quality: 94,
        );
        final file = await asset.file;
        uploadPath = file?.path;
      }

      if (!mounted || bytes == null || bytes.isEmpty) return;
      if (!widget.service.isProfileBackendAvailable) {
        showUnavailableSettingsAction(
          context,
          settingsText(context, zh: '更换头像', en: 'Change avatar'),
        );
        return;
      }
      if (uploadPath == null || uploadPath.isEmpty) {
        showSettingsMessage(
          context,
          settingsText(
            context,
            zh: '当前平台暂无法上传该图片',
            en: 'This image cannot be uploaded on the current platform.',
          ),
        );
        return;
      }
      await widget.service.updateAvatar(uploadPath);
      if (!mounted) return;
      widget.store.setProfileAvatarPreview(Uint8List.fromList(bytes));
    } catch (_) {
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(
          context,
          zh: '无法读取图片，请检查相机或相册权限后重试',
          en: 'Unable to read the image. Check camera or photo permissions and try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _pickingAvatar = false);
    }
  }

  Future<void> _viewAvatar() async {
    if (!mounted) return;
    final bytes = widget.store.profileAvatarPreviewBytes;
    final url = widget.avatarUrl;
    if (bytes == null && !IMUtils.isUrlValid(url)) {
      showSettingsMessage(
        context,
        settingsText(context, zh: '暂无可查看的头像', en: 'No avatar to preview'),
      );
      return;
    }
    await IMUtils.previewMediaFile(
      context: context,
      message: Message(),
      sources: [
        MediaSource(
          thumbnail: url,
          url: url,
          bytes: bytes,
          senderName: widget.store.profileNickname.trim().isEmpty
              ? widget.nickname
              : widget.store.profileNickname,
        ),
      ],
      showGallery: false,
      showCounter: false,
    );
  }

  String _genderLabel() {
    switch (_gender) {
      case 1:
        return settingsText(context, zh: '男', en: 'Male');
      case 2:
        return settingsText(context, zh: '女', en: 'Female');
      default:
        return settingsText(context, zh: '未填写', en: 'Not filled');
    }
  }

  Future<void> _chooseGender() async {
    if (_savingProfile) return;
    final selected = await showSettingsActionSheet<int>(
      context,
      title: settingsText(context, zh: '性别', en: 'Gender'),
      actions: [
        SettingsAction(settingsText(context, zh: '男', en: 'Male'), 1,
            enabled: _gender != 1),
        SettingsAction(settingsText(context, zh: '女', en: 'Female'), 2,
            enabled: _gender != 2),
      ],
    );
    if (selected == null || selected == _gender || !mounted) return;
    if (!widget.service.isProfileBackendAvailable) {
      showUnavailableSettingsAction(
          context, settingsText(context, zh: '修改性别', en: 'Update gender'));
      return;
    }
    await _saveProfile(() async {
      await widget.service.updateGender(selected);
      if (mounted) setState(() => _gender = selected);
    });
  }

  DateTime _birthDate() {
    if (_birth <= 0) return DateTime.now();
    final millis = _birth < 100000000000 ? _birth * 1000 : _birth;
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final min = DateTime(1900);
    final now = DateTime.now();
    if (date.isBefore(min) || date.isAfter(now)) return now;
    return date;
  }

  String _birthLabel() {
    if (_birth <= 0) return settingsText(context, zh: '未填写', en: 'Not filled');
    final date = _birthDate();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  Future<void> _chooseBirthday() async {
    if (_savingProfile) return;
    var selected = _birthDate();
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final dark = settingsIsDark(sheetContext);
        return Container(
          decoration: BoxDecoration(
            color: AppTokens.surface(dark: dark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: Text(
                            settingsText(sheetContext, zh: '取消', en: 'Cancel')),
                      ),
                      Expanded(
                        child: Text(
                          settingsText(sheetContext,
                              zh: '选择生日', en: 'Choose Birthday'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTokens.textPrimary(dark: dark),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext, selected),
                        child: Text(
                            settingsText(sheetContext, zh: '完成', en: 'Done')),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 220,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: selected,
                    minimumDate: DateTime(1900),
                    maximumDate: DateTime.now(),
                    onDateTimeChanged: (value) => selected = value,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    if (!widget.service.isProfileBackendAvailable) {
      showUnavailableSettingsAction(
          context, settingsText(context, zh: '修改生日', en: 'Update birthday'));
      return;
    }
    final value =
        DateTime(picked.year, picked.month, picked.day).millisecondsSinceEpoch;
    await _saveProfile(() async {
      await widget.service.updateBirthday(value);
      if (mounted) setState(() => _birth = value);
    });
  }

  Future<void> _copyId() async {
    final id = widget.account.trim();
    if (id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    showSettingsMessage(
      context,
      settingsText(context, zh: '99号ID已复制', en: '99 ID copied'),
    );
  }

  Future<void> _saveProfile(Future<void> Function() save) async {
    if (_savingProfile) return;
    setState(() => _savingProfile = true);
    try {
      await save();
    } catch (_) {
      if (mounted) {
        showSettingsMessage(
            context,
            settingsText(context,
                zh: '保存失败，请稍后重试', en: 'Failed to save. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _openPhone() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangePhonePage(
          service: widget.service,
          isBound: widget.phoneNumber.trim().isNotEmpty,
          currentPhone: widget.phoneNumber,
        ),
      ),
    );
  }

  void _openMoments() {
    if (widget.onMomentsTap != null) {
      widget.onMomentsTap!();
      return;
    }
    showUnavailableSettingsAction(
      context,
      settingsText(context, zh: '朋友圈', en: 'Moments'),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final signature = widget.store.profileSignature.trim();
          return SettingsScaffold(
            title: settingsText(context, zh: '个人资料', en: 'Profile'),
            children: [
              SettingsGroup(
                children: [
                  SettingsCell(
                    title: settingsText(context, zh: '头像', en: 'Avatar'),
                    value: _pickingAvatar
                        ? settingsText(context, zh: '处理中…', en: 'Processing…')
                        : null,
                    trailing: _avatar(size: 48),
                    enabled: !_pickingAvatar,
                    onTap: _changeAvatar,
                  ),
                  SettingsCell(
                    title: settingsText(context, zh: '名字', en: 'Name'),
                    value: widget.store.profileNickname.trim().isEmpty
                        ? settingsText(context, zh: '未填写', en: 'Not filled')
                        : widget.store.profileNickname.trim(),
                    onTap: () => openSettingsPage(
                      context,
                      EditNicknamePage(
                        initialNickname: widget.store.profileNickname,
                        avatarUrl: widget.avatarUrl,
                        onChangeAvatar: _changeAvatar,
                        service: widget.service,
                        store: widget.store,
                      ),
                    ),
                  ),
                  SettingsCell(
                    title: settingsText(context, zh: '性别', en: 'Gender'),
                    value: _genderLabel(),
                    onTap: _chooseGender,
                  ),
                  SettingsCell(
                    title: settingsText(context, zh: '生日', en: 'Birthday'),
                    value: _birthLabel(),
                    onTap: _chooseBirthday,
                  ),
                  SettingsCell(
                    title: settingsText(context, zh: '手机号', en: 'Phone'),
                    value: widget.phoneNumber.trim().isEmpty
                        ? settingsText(context, zh: '未绑定', en: 'Not linked')
                        : widget.phoneNumber.trim(),
                    onTap: _openPhone,
                  ),
                  SettingsCell(
                    title: settingsText(context, zh: '99号ID', en: '99 ID'),
                    value: widget.account.trim().isEmpty
                        ? '--'
                        : widget.account.trim(),
                    onTap: _copyId,
                  ),
                  SettingsCell(
                    title: settingsText(context, zh: '我的二维码', en: 'My QR Code'),
                    trailing: Icon(
                      Icons.qr_code_rounded,
                      size: 22,
                      color: settingsSecondaryTextColor(context),
                    ),
                    onTap: () => openSettingsPage(
                      context,
                      QrProfilePage(
                        nickname: widget.store.profileNickname,
                        userId: widget.userId,
                        account: widget.account,
                        avatarUrl: widget.avatarUrl,
                        avatarBytes: widget.store.profileAvatarPreviewBytes,
                      ),
                    ),
                  ),
                  SettingsCell(
                    title: settingsText(context, zh: '朋友圈', en: 'Moments'),
                    value: settingsText(context,
                        zh: '查看我的动态', en: 'View my posts'),
                    onTap: _openMoments,
                  ),
                  SettingsCell(
                    title: settingsText(context, zh: '个性签名', en: 'Bio'),
                    subtitle: signature.isEmpty
                        ? settingsText(context, zh: '未填写', en: 'Not filled')
                        : signature,
                    showDivider: false,
                    onTap: () => openSettingsPage(
                      context,
                      EditSignaturePage(
                        store: widget.store,
                        service: widget.service,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );

  Widget _avatar({required double size, bool square = false}) {
    final bytes = widget.store.profileAvatarPreviewBytes;
    if (bytes == null) {
      return AvatarView(
        url: widget.avatarUrl,
        text: widget.store.profileNickname.isEmpty
            ? widget.nickname
            : widget.store.profileNickname,
        width: size,
        height: size,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(square ? 0 : size / 2),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}
