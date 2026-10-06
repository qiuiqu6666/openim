import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'content/customer_service_content.dart';
import 'customer_service_controller.dart';
import 'customer_service_page.dart';
import 'customer_service_tokens.dart';

bool _showingCustomerService = false;

Future<void> showCustomerServiceSheet(BuildContext context,
    {bool guest = false, CustomerServiceController? controller}) async {
  if (_showingCustomerService) return;
  _showingCustomerService = true;
  FocusScope.of(context).unfocus();
  try {
    await showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: customerServiceText(context,
          zh: '关闭在线客服', en: 'Close customer service'),
      barrierColor: Theme.of(context)
          .colorScheme
          .scrim
          .withValues(alpha: CustomerServiceTokens.scrimOpacity),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : CustomerServiceTokens.sheetDuration,
      pageBuilder: (_, __, ___) => Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: CustomerServiceTokens.sheetHeightFactor,
          widthFactor: 1,
          child: CustomerServiceSheet(controller: controller, guest: guest),
        ),
      ),
      transitionBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
            CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    );
  } finally {
    _showingCustomerService = false;
  }
}

class CustomerServiceSheet extends StatelessWidget {
  const CustomerServiceSheet({super.key, this.controller, this.guest = false});
  final CustomerServiceController? controller;
  final bool guest;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = media.viewInsets.bottom > 0
        ? media.viewInsets.bottom
        : media.padding.bottom;
    return Material(
      key: const ValueKey('customer-service-sheet'),
      color: CustomerServiceTokens.surface(context),
      borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CustomerServiceTokens.sheetRadius)),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
          builder: (_, constraints) => Stack(children: [
                Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: math.min(bottom, constraints.maxHeight),
                    child: CustomerServicePage(
                        controller: controller, guest: guest)),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    key: const ValueKey('customer-service-close'),
                    tooltip:
                        customerServiceText(context, zh: '关闭', en: 'Close'),
                    onPressed: () => Navigator.of(context).pop(),
                    constraints: const BoxConstraints.tightFor(
                        width: CustomerServiceTokens.closeTapSize,
                        height: CustomerServiceTokens.closeTapSize),
                    alignment: Alignment.topRight,
                    padding: EdgeInsets.zero,
                    icon: Container(
                      width: CustomerServiceTokens.closeSize,
                      height: CustomerServiceTokens.closeSize,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.scrim.withValues(
                              alpha: CustomerServiceTokens.scrimOpacity)),
                      child: const Icon(Icons.close_rounded,
                          size: CustomerServiceTokens.faqIconSize,
                          color: AppTokens.onAccent),
                    ),
                  ),
                ),
              ])),
    );
  }
}
