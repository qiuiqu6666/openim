import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../user_profile_tokens.dart';
import 'set_remark_logic.dart';
import 'widgets/name_editor_input.dart';

class SetFriendRemarkPage extends StatelessWidget {
  factory SetFriendRemarkPage({Key? key, SetFriendRemarkLogic? logic}) {
    final editor = logic ?? Get.find<SetFriendRemarkLogic>();
    return SetFriendRemarkPage.editor(
      key: key,
      controller: editor.inputCtrl,
      avatarURL: editor.avatarURL,
      avatarName: editor.avatarName,
      maxLength: SetFriendRemarkLogic.maxRemarkLength,
      onSave: editor.save,
      hintText: editor.avatarName,
      remarkLayout: true,
    );
  }

  const SetFriendRemarkPage.editor({
    super.key,
    required this.controller,
    required this.onSave,
    required this.maxLength,
    this.avatarURL,
    this.avatarName,
    this.avatarBytes,
    this.keyboardType,
    this.onAvatarTap,
    this.isGroupAvatar = false,
    this.saving = false,
    this.footer,
    this.saveEnabled = true,
    this.inputStatus,
    this.hintText,
    this.showClearButton = false,
    this.remarkLayout = false,
  });

  final TextEditingController controller;
  final VoidCallback onSave;
  final int maxLength;
  final String? avatarURL;
  final String? avatarName;
  final Uint8List? avatarBytes;
  final TextInputType? keyboardType;
  final VoidCallback? onAvatarTap;
  final bool isGroupAvatar;
  final bool saving;
  final Widget? footer;
  final bool saveEnabled;
  final Widget? inputStatus;
  final String? hintText;
  final bool showClearButton;
  final bool remarkLayout;

  VoidCallback? _avatarTap(BuildContext context) => saving
      ? null
      : onAvatarTap ??
          (AvatarActions.canPreview(url: avatarURL, bytes: avatarBytes)
              ? () => AvatarActions.preview(context,
                  url: avatarURL, bytes: avatarBytes)
              : null);
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: remarkLayout ? Styles.c_FFFFFF : Styles.c_F4F5F7,
        appBar: GlassAppBar(
          opaque: true,
          toolbarHeight: NavigationGlassTokens.toolbarHeight,
          backgroundColor: remarkLayout ? Styles.c_FFFFFF : Styles.c_F4F5F7,
          surfaceTintColor: remarkLayout ? Styles.c_FFFFFF : Styles.c_F4F5F7,
          title: remarkLayout
              ? Text(StrRes.nickname,
                  style: TextStyle(
                    color: UserProfileTokens.text(context),
                    fontSize: UserProfileTokens.rowFontSize,
                    fontWeight: FontWeight.w600,
                  ))
              : null,
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: saving ? null : () => Navigator.of(context).maybePop(),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(
              remarkLayout
                  ? Icons.arrow_back_ios_new_rounded
                  : Icons.arrow_back_ios_new,
              size: remarkLayout ? UserProfileTokens.navigationIconSize : 24.w,
              color: Styles.c_0089FF,
            ),
          ),
          actions: [
            if (!remarkLayout) ...[
              TextButton(
                onPressed: saving || !saveEnabled ? null : onSave,
                child: saving
                    ? SizedBox(
                        width: AppTokens.s6,
                        height: AppTokens.s6,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTokens.accent,
                        ),
                      )
                    : Text(StrRes.determine,
                        style: TextStyle(
                            color: saveEnabled
                                ? Styles.c_0089FF
                                : Theme.of(context).disabledColor,
                            fontSize: 16.sp)),
              ),
              6.horizontalSpace,
            ],
          ],
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: AppTokens.rLg.w,
              vertical: remarkLayout ? AppTokens.rLg.h : AppTokens.s7.h,
            ),
            child: Column(children: [
              if (!remarkLayout) ...[
                Center(
                  child: avatarBytes != null
                      ? GestureDetector(
                          onTap: _avatarTap(context),
                          child: ClipOval(
                            child: Image.memory(
                              avatarBytes!,
                              width: 96.w,
                              height: 96.w,
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      : AvatarView(
                          onTap: _avatarTap(context),
                          url: avatarURL,
                          text: avatarName,
                          isGroup: isGroupAvatar,
                          isCircle: true,
                          width: 96.w,
                          height: 96.w,
                          textStyle: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 40.sp),
                        ),
                ),
                30.verticalSpace,
              ],
              NameEditorInput(
                remarkLayout: remarkLayout,
                controller: controller,
                maxLength: maxLength,
                keyboardType: keyboardType,
                onSave: onSave,
                hintText: hintText,
                showClearButton: showClearButton,
                saving: saving,
                saveEnabled: saveEnabled,
                inputStatus: inputStatus,
              ),
              if (remarkLayout) ...[
                SizedBox(height: AppTokens.s7.h + AppTokens.s2.h),
                Button(
                  text: StrRes.done,
                  onTap: onSave,
                  enabled: saveEnabled,
                  loading: saving,
                  height: (AppTokens.s7 * 2).h,
                  radius: AppTokens.s2.r,
                  enabledColor: Styles.c_0089FF,
                  textStyle: TextStyle(
                      color: AppTokens.onAccent,
                      fontSize: AppTokens.secondaryFontSize.sp),
                ),
              ],
              if (footer != null) footer!,
            ]),
          ),
        ),
      );
}
