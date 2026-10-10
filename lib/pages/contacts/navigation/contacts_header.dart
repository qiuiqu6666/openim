import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/im_callback.dart';
import '../../home/home_quick_actions.dart';

/// Main contacts navigation from 99chat's home_page.dart, using SDK status.
class ContactsHeader extends StatefulWidget implements PreferredSizeWidget {
  const ContactsHeader({
    super.key,
    required this.onSearchAdd,
    required this.onCreateGroup,
    required this.onScan,
    this.sdkStatus,
    this.initialStatus,
    this.toolbarHeight = kToolbarHeight,
  });

  final VoidCallback onSearchAdd;
  final VoidCallback onCreateGroup;
  final VoidCallback onScan;
  final Stream<IMSdkStatus>? sdkStatus;
  final IMSdkStatus? initialStatus;
  final double toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  State<ContactsHeader> createState() => _ContactsHeaderState();
}

class _ContactsHeaderState extends State<ContactsHeader> {
  final _plusKey = GlobalKey();
  double _plusTurns = 0;
  bool _menuOpen = false;

  Future<void> _openMenu() async {
    if (_menuOpen) return;
    _menuOpen = true;
    setState(() => _plusTurns += .125);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    try {
      await showHomeQuickActions(context: context, anchor: _plusKey, actions: [
        HomeQuickAction(
            id: 'searchAdd',
            title: zh ? '搜索添加' : 'Search & Add',
            subtitle: zh ? '通过账号/手机号搜索好友' : 'Find friends by account or phone',
            onTap: widget.onSearchAdd),
        HomeQuickAction(
            id: 'createGroup',
            title: StrRes.createGroup,
            subtitle: zh ? '发起多人聊天' : 'Start a group conversation',
            onTap: widget.onCreateGroup),
        HomeQuickAction(
            id: 'createChannel',
            title: zh ? '创建频道' : 'Create Channel',
            subtitle: zh ? '暂未开放' : 'Coming soon',
            enabled: false),
        HomeQuickAction(
            id: 'scanQRCode',
            title: StrRes.scan,
            subtitle: zh ? '扫描二维码添加好友' : 'Scan a QR code to add friends',
            onTap: widget.onScan),
      ]);
    } finally {
      _menuOpen = false;
      if (mounted) setState(() => _plusTurns += .125);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? AppTokens.backgroundDark : AppTokens.surfaceLight;
    return GlassAppBar(
      toolbarHeight: widget.toolbarHeight,
      backgroundColor: background,
      foregroundColor: AppTokens.textPrimary(dark: dark),
      automaticallyImplyLeading: false,
      centerTitle: false,
      titleSpacing: AppTokens.s5,
      systemOverlayStyle: AppSystemBars.styleFor(background),
      title: StreamBuilder<IMSdkStatus>(
        stream: widget.sdkStatus,
        initialData: widget.initialStatus,
        builder: (context, snapshot) {
          final status = snapshot.data;
          return MainTabTitle(
            keyPrefix: 'contacts-title',
            title: StrRes.contacts,
            busy: const {
              IMSdkStatus.connecting,
              IMSdkStatus.syncStart,
              IMSdkStatus.synchronizing,
              IMSdkStatus.syncProgress,
            }.contains(status),
            busyLabel: const {
              IMSdkStatus.syncStart,
              IMSdkStatus.synchronizing,
              IMSdkStatus.syncProgress,
            }.contains(status)
                ? StrRes.synchronizing
                : null,
            failed: status == IMSdkStatus.connectionFailed ||
                status == IMSdkStatus.syncFailed,
          );
        },
      ),
      actions: [
        MainTabPlusButton(
            buttonKey: _plusKey, turns: _plusTurns, onPressed: _openMenu),
      ],
    );
  }
}
