import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;

/// Keeps public ledger status visible even inside a transparent sheet route.
class SangongProfileLedgerFrame extends StatelessWidget {
  const SangongProfileLedgerFrame(
      {super.key, required this.child, this.embedded = false});

  final Widget child;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: AppTokens.surface(dark: dark),
      child: SafeArea(
        child: Column(children: [
          ListTile(
            title: Text(AppCopy.text('游戏流水'),
                style: TextStyle(color: AppTokens.textPrimary(dark: dark))),
            trailing: embedded
                ? null
                : IconButton(
                    tooltip: AppCopy.text('关闭'),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
          ),
          Expanded(child: child),
        ]),
      ),
    );
  }
}
