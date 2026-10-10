import 'package:flutter/material.dart';

import '../../../routes/app_navigator.dart';
import '../../../widgets/auth/auth_copy.dart';
import '../../../widgets/auth/auth_reference_tokens.dart';
import '../../customer_service/customer_service.dart';
import '../../mine/settings/pages/node_switch_page.dart';
import '../../mine/settings/settings_draft_store.dart';
import '../../mine/settings/settings_navigation.dart';
import '../../mine/settings/settings_service.dart';

/// Public entry points remain available before an account is signed in.
class LoginToolbar extends StatelessWidget {
  const LoginToolbar(
      {super.key, this.customerServiceOnly = false, this.onHero = true});
  final bool customerServiceOnly;

  /// Blue entry heroes keep white actions; plain forms use theme foregrounds.
  final bool onHero;

  Future<void> _showNodes(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final store = SettingsDraftStore();
    try {
      await openSettingsPage(
          context,
          NodeSwitchPage(
            store: store,
            service: const StubSettingsService(),
          ));
    } finally {
      store.dispose();
    }
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
              onHero: onHero,
              label: authText('在线客服', 'Customer service'),
              onPressed: () => showCustomerServiceSheet(context, guest: true),
            ),
            if (!customerServiceOnly) ...[
              const SizedBox(width: AuthReferenceTokens.toolbarGap),
              _ToolbarAction(
                actionKey: const ValueKey('login-nodes'),
                icon: Icons.dns_outlined,
                onHero: onHero,
                label: authText('节点切换', 'Switch node'),
                onPressed: () => _showNodes(context),
              ),
              const SizedBox(width: AuthReferenceTokens.toolbarGap),
              _ToolbarAction(
                actionKey: const ValueKey('login-language'),
                icon: Icons.language_outlined,
                onHero: onHero,
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
    required this.onHero,
  });

  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool onHero;

  @override
  Widget build(BuildContext context) => IconButton(
        key: actionKey,
        onPressed: onPressed,
        tooltip: label,
        color: onHero ? Colors.white : Theme.of(context).colorScheme.onSurface,
        iconSize: AuthReferenceTokens.toolbarIcon,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: onHero
              ? Colors.white.withValues(alpha: .08)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: .05),
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
