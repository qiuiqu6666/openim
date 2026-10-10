import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim_common/openim_common.dart';
import '../../../contacts/group_profile_panel/group_profile_panel_logic.dart';
import '../../../../routes/app_navigator.dart';
import '../../../contacts/group_profile_panel/group_profile_panel_logic.dart'
    show JoinGroupMethod;
import 'group_qrcode_background.dart';

class GroupQrcodeLogic extends GetxController {
  final groupSetupLogic = Get.find<GroupSetupLogic>();
  final cardKey = GlobalKey();
  final saving = false.obs;
  final scanning = false.obs;

  String get displayGroupId {
    final id = groupSetupLogic.groupInfo.value.groupID.trim();
    if (id.isEmpty) return '';
    return id.startsWith('@') ? id : '@$id';
  }

  Future<void> copyGroupId() async {
    if (displayGroupId.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: displayGroupId));
    if (!isClosed) IMViews.showToast(StrRes.copySuccessfully);
  }

  Future<void> saveToAlbum() async {
    if (saving.value) return;
    saving.value = true;
    ui.Image? image;
    try {
      final context = cardKey.currentContext;
      if (context == null) throw StateError('QR card not ready');
      await precacheImage(groupQrcodeWatermarkImage, context);
      await WidgetsBinding.instance.endOfFrame;
      final boundary = cardKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary || boundary.debugNeedsPaint) {
        throw StateError('QR card not ready');
      }
      image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not encode QR card');
      final file = File(
          '${Config.cachePath}/group_qr_${DateTime.now().microsecondsSinceEpoch}.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await HttpUtil.saveFileToGallerySaver(file);
    } catch (_) {
      if (!isClosed) IMViews.showToast(StrRes.saveFailed);
    } finally {
      image?.dispose();
      if (!isClosed) saving.value = false;
    }
  }

  Future<void> scan() async {
    if (scanning.value) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      IMViews.showToast('groupQrMobileOnly'.tr);
      return;
    }
    scanning.value = true;
    try {
      final id = await Get.to<String>(() => const GroupQrScanner());
      if (id == null || isClosed) return;
      // New links have an @ prefix; existing OpenIM installations can store
      // the same ID without it. Resolve the real SDK ID before navigation.
      final groups = await OpenIM.iMManager.groupManager.getGroupsInfo(
        groupIDList: [id, if (id.startsWith('@')) id.substring(1)],
      );
      if (isClosed) return;
      if (groups.isEmpty) {
        IMViews.showToast('groupQrNotFound'.tr);
        return;
      }
      await AppNavigator.startGroupProfilePanel(
          groupID: groups.first.groupID,
          joinGroupMethod: JoinGroupMethod.qrcode);
    } catch (_) {
      if (!isClosed) IMViews.showToast('groupQrScanFailed'.tr);
    } finally {
      if (!isClosed) scanning.value = false;
    }
  }

  String buildQRContent() {
    final groupID = groupSetupLogic.groupInfo.value.groupID.trim();
    final id = groupID.startsWith('@') ? groupID.substring(1) : groupID;
    return '${Config.groupScheme}@${Uri.encodeComponent(id)}';
  }
}
