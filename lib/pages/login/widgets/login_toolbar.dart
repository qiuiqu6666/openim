import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../routes/app_navigator.dart';
import '../../../widgets/auth/auth_copy.dart';
import '../../../widgets/auth/auth_reference_tokens.dart';
import '../../customer_service/customer_service.dart';

/// Public entry points remain available before an account is signed in.
class LoginToolbar extends StatelessWidget {
  const LoginToolbar({super.key, this.customerServiceOnly = false});
  final bool customerServiceOnly;

  Future<void> _showNodes(BuildContext context) async {
    FocusScope.of(context).unfocus();
    // The settings page's node labels are not endpoint configurations. Expose
    // only the active configuration until the backend supplies alternatives.
    await showAppActionSheet<String>(
      context,
      title: authText(
        '切换节点 · 当前仅配置了一个节点',
        'Switch node · One node is currently configured',
      ),
      actions: [
        AppAction(
          authText('当前节点', 'Current node'),
          'current',
          selected: true,
          subtitle: 'Chat API: ${Config.appAuthUrl}\n'
              'OpenIM API: ${Config.imApiUrl}\n'
              'OpenIM WebSocket: ${Config.imWsUrl}',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolbarAction(
              actionKey: const ValueKey('login-customer-service'),
              icon: Icons.headset_mic_outlined,
              label: authText('在线客服', 'Customer service'),
              onPressed: () => showCustomerServiceSheet(context, guest: true),
            ),
            if (!customerServiceOnly) ...[
              const SizedBox(width: AuthReferenceTokens.toolbarGap),
              _ToolbarAction(
                actionKey: const ValueKey('login-nodes'),
                icon: Icons.dns_outlined,
                label: authText('节点切换', 'Switch node'),
                onPressed: () => _showNodes(context),
              ),
              const SizedBox(width: AuthReferenceTokens.toolbarGap),
              _ToolbarAction(
                actionKey: const ValueKey('login-language'),
                icon: Icons.language_outlined,
                label: authText('切换语言', 'Switch language'),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  AppNavigator.startLanguageSetup();
                },
              ),
            ],
          ],
        ),
      );
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        key: actionKey,
        onPressed: onPressed,
        tooltip: label,
        color: Colors.white,
        iconSize: AuthReferenceTokens.toolbarIcon,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: .08),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AuthReferenceTokens.rLg)),
        ),
        visualDensity: VisualDensity.standard,
        constraints: const BoxConstraints(
          minWidth: AuthReferenceTokens.tapTarget,
          minHeight: AuthReferenceTokens.tapTarget,
        ),
        icon: Icon(icon),
      );
}
