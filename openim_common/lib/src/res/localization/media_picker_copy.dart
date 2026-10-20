import 'dart:ui';

import 'package:get/get.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

import 'app_copy.dart';

/// Explicit delegates avoid plugins treating zh_TW as generic simplified zh.
class AppMediaCopy {
  AppMediaCopy._();

  static Locale? get _locale => Get.locale ?? Get.deviceLocale;

  static AssetPickerTextDelegate get assets => assetsFor(_locale);
  static CameraPickerTextDelegate get camera => cameraFor(_locale);

  static AssetPickerTextDelegate assetsFor(Locale? locale) {
    if (AppCopy.isTraditional(locale)) {
      return const TraditionalChineseAssetPickerTextDelegate();
    }
    return locale?.languageCode == 'en'
        ? const EnglishAssetPickerTextDelegate()
        : const AssetPickerTextDelegate();
  }

  static CameraPickerTextDelegate cameraFor(Locale? locale) {
    if (AppCopy.isTraditional(locale)) {
      return const TraditionalCameraPickerTextDelegate();
    }
    return locale?.languageCode == 'en'
        ? const EnglishCameraPickerTextDelegate()
        : const CameraPickerTextDelegate();
  }
}

/// The installed camera picker supplies simplified Chinese and English only.
class TraditionalCameraPickerTextDelegate extends CameraPickerTextDelegate {
  const TraditionalCameraPickerTextDelegate();

  @override
  String get confirm => '確認';
  @override
  String get shootingTips => '輕觸拍照';
  @override
  String get shootingWithRecordingTips => '輕觸拍照，長按錄影';
  @override
  String get shootingOnlyRecordingTips => '長按錄影';
  @override
  String get shootingTapRecordingTips => '輕觸錄影';
  @override
  String get loadFailed => '載入失敗';
  @override
  String get loading => '載入中…';
  @override
  String get saving => '儲存中…';
  @override
  String get sActionManuallyFocusHint => '手動對焦';
  @override
  String get sActionPreviewHint => '預覽';
  @override
  String get sActionRecordHint => '錄影';
  @override
  String get sActionShootHint => '拍照';
  @override
  String get sActionShootingButtonTooltip => '拍照按鈕';
  @override
  String get sActionStopRecordingHint => '停止錄影';

  @override
  String sCameraLensDirectionLabel(CameraLensDirection value) =>
      switch (value) {
        CameraLensDirection.front => '前置',
        CameraLensDirection.back => '後置',
        CameraLensDirection.external => '外置',
      };

  @override
  String? sCameraPreviewLabel(CameraLensDirection? value) =>
      value == null ? null : '${sCameraLensDirectionLabel(value)}畫面預覽';

  @override
  String sFlashModeLabel(FlashMode mode) => '閃光模式: ${switch (mode) {
        FlashMode.off => '關閉',
        FlashMode.auto => '自動',
        FlashMode.always => '拍照時閃光',
        FlashMode.torch => '持續閃光',
      }}';

  @override
  String sSwitchCameraLensDirectionLabel(CameraLensDirection value) =>
      '切換至${sCameraLensDirectionLabel(value)}鏡頭';
}
