import 'package:openim_common/media_localization.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common_utils/common_utils.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_picker_plus/flutter_picker_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';
import 'package:uuid/uuid.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

import '../utils/http/transport_error_messages.dart';

class IMViews {
  IMViews._();

  static Future showToast(String msg,
      {Duration? duration, bool centered = false}) {
    if (msg.trim().isNotEmpty) {
      return EasyLoading.showToast(
        TransportErrorMessages.toastText(msg),
        duration: duration,
        toastPosition: centered ? EasyLoadingToastPosition.center : null,
        maskType: EasyLoadingMaskType.none,
        dismissOnTap: false,
      );
    } else {
      return Future.value();
    }
  }

  static Future showErrorToast(Object error,
      {String? path, String? fallback, Duration? duration}) {
    if (HttpUtil.isSilentError(error, path: path)) return Future.value();
    return showToast(
        HttpUtil.errorMessage(error, path: path, fallback: fallback),
        duration: duration);
  }

  static Widget buildHeader([double distance = 60]) => WaterDropMaterialHeader(
        backgroundColor: Styles.c_0089FF,
        distance: distance,
      );

  static Widget buildFooter() => CustomFooter(
        builder: (BuildContext context, LoadStatus? mode) {
          Widget body;
          if (mode == LoadStatus.idle) {
            body = const CupertinoActivityIndicator();
          } else if (mode == LoadStatus.loading) {
            body = const CupertinoActivityIndicator();
          } else if (mode == LoadStatus.failed) {
            body = const CupertinoActivityIndicator();
          } else if (mode == LoadStatus.canLoading) {
            body = const CupertinoActivityIndicator();
          } else {
            body = const SizedBox();
          }
          return SizedBox(
            height: 55.0,
            child: Center(child: body),
          );
        },
      );

  static openIMCallSheet(
    String label,
    Function(int index) onTapSheetItem,
  ) {
    return Get.bottomSheet(
      BottomSheetView(
        items: [
          SheetItem(
            label: StrRes.callVoice,
            onTap: () => onTapSheetItem.call(0),
          ),
          SheetItem(
            label: StrRes.callVideo,
            onTap: () => onTapSheetItem.call(1),
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
    );
  }

  static openIMGroupCallSheet(
    String groupID,
    Function(int index) onTapSheetItem,
  ) {
    return Get.bottomSheet(
      BottomSheetView(
        mainAxisAlignment: MainAxisAlignment.start,
        items: [
          SheetItem(
            label: StrRes.callVoice,
            icon: ImageRes.callVoice,
            onTap: () => onTapSheetItem.call(0),
          ),
          SheetItem(
            label: StrRes.callVideo,
            icon: ImageRes.callVideo,
            onTap: () => onTapSheetItem.call(1),
          ),
        ],
      ),
    );
  }

  static void openPhotoSheet(
      {Function(dynamic path, dynamic url)? onData,
      String? avatarUrl,
      bool Function()? isActive,
      bool crop = true,
      bool toUrl = true,
      bool fromGallery = true,
      bool fromCamera = true,
      List<SheetItem> items = const [],
      int quality = 80}) async {
    final context = Get.context;
    if (context == null || !context.mounted || isActive?.call() == false) {
      return;
    }
    bool allowSendImageTypeHelper(String? mimeType) {
      final result = mimeType?.contains('png') == true ||
          mimeType?.contains('jpeg') == true;

      return result;
    }

    Future<bool> allowSendImageType(AssetEntity entity) async {
      final mimeType = await entity.mimeTypeAsync;

      return allowSendImageTypeHelper(mimeType);
    }

    final itemsToShow = [
      if (AvatarActions.canPreview(url: avatarUrl))
        SheetItem(
          label: StrRes.viewAvatar,
          onTap: () => AvatarActions.preview(context, url: avatarUrl),
        ),
      ...items,
      if (fromGallery)
        SheetItem(
          label: StrRes.toolboxAlbum,
          onTap: () async {
            final List<AssetEntity>? assets =
                await AssetPicker.pickAssets(context,
                    pickerConfig: AssetPickerConfig(
                        textDelegate: AppMediaCopy.assets,
                        requestType: RequestType.image,
                        maxAssets: 1,
                        selectPredicate: (_, entity, isSelected) async {
                          if (await allowSendImageType(entity)) {
                            return true;
                          }

                          IMViews.showToast(StrRes.supportsTypeHint);

                          return false;
                        }));
            final file = await assets?.firstOrNull?.file;

            if (context.mounted &&
                isActive?.call() != false &&
                file?.path != null) {
              final map = await uCropPic(file!.path,
                  crop: crop, toUrl: toUrl, quality: quality);
              if (context.mounted && isActive?.call() != false) {
                onData?.call(map['path'], map['url']);
              }
            }
          },
        ),
      if (fromCamera)
        SheetItem(
          label: StrRes.toolboxCamera,
          onTap: () async {
            final AssetEntity? entity = await CameraPicker.pickFromCamera(
              context,
              locale: Get.locale,
              pickerConfig: CameraPickerConfig(
                textDelegate: AppMediaCopy.camera,
                enableAudio: true,
                enableRecording: true,
                enableScaledPreview: false,
                maximumRecordingDuration: 60.seconds,
                onMinimumRecordDurationNotMet: () {
                  IMViews.showToast(StrRes.tapTooShort);
                },
              ),
            );

            final file = await entity?.file;

            if (context.mounted &&
                isActive?.call() != false &&
                file?.path != null) {
              final map = await uCropPic(file!.path,
                  crop: crop, toUrl: toUrl, quality: quality);
              if (context.mounted && isActive?.call() != false) {
                onData?.call(map['path'], map['url']);
              }
            }
          },
        ),
    ];
    final selected = await showAppActionSheet<SheetItem>(
      context,
      title: StrRes.avatar,
      actions: [for (final item in itemsToShow) AppAction(item.label, item)],
    );
    if (context.mounted && isActive?.call() != false) selected?.onTap?.call();
  }

  static Future<Map<String, dynamic>> uCropPic(
    String path, {
    bool crop = true,
    bool toUrl = true,
    int quality = 80,
  }) async {
    CroppedFile? cropFile;
    String? url;
    if (crop && !path.endsWith('.gif')) {
      cropFile = await IMUtils.uCrop(path);
      if (cropFile == null) {
        return {'path': null, 'url': null};
      }
    }
    if (toUrl) {
      String putID = const Uuid().v4();
      dynamic result;
      if (null != cropFile) {
        Logger.print('-----------crop path: ${cropFile.path}');
        result = await LoadingView.singleton.wrap(asyncFunction: () async {
          final image = await IMUtils.compressImageAndGetFile(
              File(cropFile!.path),
              quality: quality);

          return OpenIM.iMManager.uploadFile(
            id: putID,
            filePath: image!.path,
            fileName: image.path.split('/').last,
          );
        });
      } else {
        Logger.print('-----------source path: $path');
        result = await LoadingView.singleton.wrap(asyncFunction: () async {
          final image = await IMUtils.compressImageAndGetFile(File(path),
              quality: quality);

          return OpenIM.iMManager.uploadFile(
            id: putID,
            filePath: image!.path,
            fileName: image.path,
          );
        });
      }
      if (result is String) {
        url = jsonDecode(result)['url'];
        Logger.print('url:$url');
      }
    }
    return {'path': cropFile?.path ?? path, 'url': url};
  }

  static void openDownloadSheet(
    String url, {
    Function()? onDownload,
  }) {
    Get.bottomSheet(
      BottomSheetView(
        items: [
          SheetItem(
            label: StrRes.download,
            onTap: () {
              Permissions.storage(() => onDownload?.call());
            },
          ),
        ],
      ),
      barrierColor: Colors.transparent,
    );
  }

  static TextSpan getTimelineTextSpan(int ms) {
    int locTimeMs = DateTime.now().millisecondsSinceEpoch;
    var languageCode = Get.locale?.languageCode ?? 'zh';

    if (DateUtil.isToday(ms, locMs: locTimeMs)) {
      return TextSpan(
        text: languageCode == 'zh' ? '今天' : 'Today',
        style: Styles.ts_0C1C33_17sp_medium,
      );
    }

    if (DateUtil.isYesterdayByMs(ms, locTimeMs)) {
      return TextSpan(
        text: languageCode == 'zh' ? '昨天' : 'Yesterday',
        style: Styles.ts_0C1C33_17sp_medium,
      );
    }

    if (DateUtil.isWeek(ms, locMs: locTimeMs)) {
      final weekday = DateUtil.getWeekdayByMs(ms, languageCode: languageCode);
      if (weekday.contains('星期')) {
        return TextSpan(
          text: weekday.replaceAll('星期', ''),
          style: Styles.ts_0C1C33_17sp_medium,
          children: [
            TextSpan(
              text: '\n星期',
              style: Styles.ts_0C1C33_12sp_medium,
            ),
          ],
        );
      }
      return TextSpan(text: weekday, style: Styles.ts_0C1C33_17sp_medium);
    }

    final date = IMUtils.formatDateMs(ms, format: 'MM月dd');
    final one = date.split('月')[0];
    final two = date.split('月')[1];
    return TextSpan(
      text: '${int.parse(two)}',
      style: Styles.ts_0C1C33_17sp_medium,
      children: [
        TextSpan(
          text: '\n${int.parse(one)}${languageCode == 'zh' ? '月' : ''}',
          style: Styles.ts_0C1C33_12sp_medium,
        ),
      ],
    );
  }

  static Future<String?> showCountryCodePicker() async {
    Completer<String> completer = Completer();
    showCountryPicker(
      context: Get.context!,
      showPhoneCode: true,
      countryListTheme: CountryListThemeData(
        flagSize: 25,
        textStyle: TextStyle(fontSize: 16.sp),
        bottomSheetHeight: 500.h,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8.0.r),
          topRight: Radius.circular(8.0.r),
        ),
        inputDecoration: InputDecoration(
          labelText: StrRes.search,
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
        ),
      ),
      onSelect: (Country country) {
        completer.complete("+${country.phoneCode}");
      },
    );
    return completer.future;
  }

  static void showSinglePicker({
    required String title,
    required String description,
    required dynamic pickerData,
    bool isArray = false,
    List<int>? selected,
    Function(List<int> indexList, List valueList)? onConfirm,
  }) {
    Picker(
      adapter: PickerDataAdapter<String>(
        pickerData: pickerData,
        isArray: isArray,
      ),
      changeToFirst: true,
      hideHeader: false,
      containerColor: Styles.c_0089FF,
      textStyle: Styles.ts_0C1C33_17sp,
      selectedTextStyle: Styles.ts_0C1C33_17sp,
      itemExtent: 45.h,
      cancelTextStyle: Styles.ts_0C1C33_17sp,
      confirmTextStyle: Styles.ts_0089FF_17sp,
      cancelText: StrRes.cancel,
      confirmText: StrRes.confirm,
      selecteds: selected,
      builderHeader: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            alignment: Alignment.centerLeft,
            margin: EdgeInsets.only(bottom: 7.h),
            child: title.toText..style = Styles.ts_0C1C33_17sp,
          ),
          description.toText..style = Styles.ts_8E9AB0_14sp,
        ],
      ),
      selectionOverlay: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: BorderDirectional(
            bottom: BorderSide(color: Styles.c_E8EAEF, width: 1),
            top: BorderSide(color: Styles.c_E8EAEF, width: 1),
          ),
        ),
      ),
      onConfirm: (Picker picker, List value) {
        onConfirm?.call(picker.selecteds, picker.getSelectedValues());
      },
    ).showDialog(Get.context!);
  }
}
