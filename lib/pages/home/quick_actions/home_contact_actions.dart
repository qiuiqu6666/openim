import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../home_quick_actions.dart';

/// One menu definition for the conversations and contacts headers.
List<HomeQuickAction> homeContactActions({
  required BuildContext context,
  required VoidCallback onSearchAdd,
  required VoidCallback onCreateGroup,
  required VoidCallback onScan,
}) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  return [
    HomeQuickAction(
        id: 'searchAdd',
        title: zh ? AppCopy.text('搜索添加') : 'Search & Add',
        subtitle: zh
            ? AppCopy.text('通过账号/手机号搜索好友')
            : 'Find friends by account or phone',
        onTap: onSearchAdd),
    HomeQuickAction(
        id: 'createGroup',
        title: StrRes.createGroup,
        subtitle: zh ? AppCopy.text('发起多人聊天') : 'Start a group conversation',
        onTap: onCreateGroup),
    HomeQuickAction(
        id: 'createChannel',
        title: zh ? AppCopy.text('创建频道') : 'Create Channel',
        subtitle: zh ? AppCopy.text('暂未开放') : 'Coming soon',
        enabled: false),
    HomeQuickAction(
        id: 'scanQRCode',
        title: StrRes.scan,
        subtitle:
            zh ? AppCopy.text('扫描好友或群二维码') : 'Scan a friend or group QR code',
        onTap: onScan),
  ];
}
