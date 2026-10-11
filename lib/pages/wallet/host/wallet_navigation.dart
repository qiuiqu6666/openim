import 'package:flutter/material.dart';

import '../widgets/wallet_99chat_tokens.dart';
import '../../../routes/swipe_back/app_page_route.dart';

export '../../../routes/swipe_back/app_page_route.dart'
    show AppMaterialPageRoute;

/// Push a Wallet secondary page above OpenIM's PersistentTabView.
///
/// The root navigator boundary keeps the five main tabs out of Wallet child
/// pages, while [AppMaterialPageRoute] mirrors 99chat's edge-swipe interaction.
Future<T?> openWalletPage<T>(BuildContext context, Widget page,
    {String activityPage = 'wallet'}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    AppMaterialPageRoute<T>(
        builder: (_) => page, settings: RouteSettings(name: '/$activityPage')),
  );
}

Future<T?> replaceWalletPage<T, TO>(BuildContext context, Widget page,
    {String activityPage = 'wallet'}) {
  return Navigator.of(context, rootNavigator: true).pushReplacement<T, TO>(
    AppMaterialPageRoute<T>(
        builder: (_) => page, settings: RouteSettings(name: '/$activityPage')),
  );
}

class AppBackButton extends StatelessWidget {
  final Color? color;
  final VoidCallback? onPressed;

  const AppBackButton({super.key, this.color, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded),
      color: color ?? AppTokens.accent,
      onPressed: onPressed ??
          () => Navigator.of(context, rootNavigator: true).maybePop(),
    );
  }
}
