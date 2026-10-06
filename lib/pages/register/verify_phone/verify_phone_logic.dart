import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/settings/widgets/account_code_request.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../../routes/app_navigator.dart';
import '../../../widgets/auth/auth_form_rules.dart';

class VerifyPhoneLogic extends GetxController {
  final codeErrorCtrl = StreamController<ErrorAnimationType>();
  final codeEditCtrl = TextEditingController();
  final enabled = false.obs;
  final submitting = false.obs;
  bool _closed = false;
  static final _verificationCodePattern = RegExp(r'^\d{6}$');
  String? phoneNumber;
  String? email;
  late String areaCode;
  late int usedFor;
  String? invitationCode;

  String get account =>
      phoneNumber?.isNotEmpty == true ? (areaCode + phoneNumber!) : email!;
  @override
  void onInit() {
    phoneNumber = Get.arguments['phoneNumber'];
    email = Get.arguments['email'];
    areaCode = Get.arguments['areaCode'];
    usedFor = Get.arguments['usedFor'];
    invitationCode = Get.arguments['invitationCode'];
    codeEditCtrl.addListener(_onChanged);
    super.onInit();
  }

  @override
  void onClose() {
    _closed = true;
    codeEditCtrl.dispose();
    codeErrorCtrl.close();
    super.onClose();
  }

  void _onChanged() {
    enabled.value = _verificationCodePattern.hasMatch(codeEditCtrl.text);
  }

  void shake() {
    if (_closed || isClosed || codeErrorCtrl.isClosed) return;
    codeErrorCtrl.add(ErrorAnimationType.shake);
  }

  Future<bool> requestVerificationCode() {
    if (_closed || isClosed) return Future.value(false);
    final error = _accountError();
    if (error != null) {
      IMViews.showToast(error);
      return Future.value(false);
    }
    return requestAccountVerificationCode(
      areaCode: areaCode,
      phoneNumber: phoneNumber,
      email: email,
      usedFor: usedFor,
      invitationCode: invitationCode,
    );
  }

  Future checkVerificationCode(String verificationCode) =>
      Apis.checkVerificationCode(
        areaCode: areaCode,
        phoneNumber: phoneNumber,
        email: email,
        verificationCode: verificationCode,
        usedFor: usedFor,
        invitationCode: invitationCode,
      );

  Future<void> completed(String value) async {
    final verificationCode = value.trim();
    if (_closed || isClosed || submitting.value) return;
    final error = _accountError() ??
        AuthFormRules.verificationCode(verificationCode, sixDigits: true);
    if (error != null) {
      IMViews.showToast(error);
      return;
    }
    submitting.value = true;
    try {
      await LoadingView.singleton.wrap(
        asyncFunction: () async {
          if (_closed || isClosed) return;
          await checkVerificationCode(verificationCode);
        },
      );
      if (_closed || isClosed) return;
      AppNavigator.startSetPassword(
        areaCode: areaCode,
        phoneNumber: phoneNumber,
        email: email,
        verificationCode: verificationCode,
        usedFor: usedFor,
        invitationCode: invitationCode,
      );
    } catch (_) {
      shake();
    } finally {
      if (!_closed && !isClosed) submitting.value = false;
    }
  }

  String? _accountError() => email != null
      ? AuthFormRules.email(email)
      : AuthFormRules.phone(phoneNumber, areaCode);
}
