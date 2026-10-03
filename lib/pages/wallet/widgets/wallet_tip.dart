import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

class WalletTip {
  WalletTip._();

  static void show(BuildContext context, String text) {
    IMViews.showToast(text);
  }
}
