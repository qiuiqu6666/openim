import 'package:flutter/material.dart';

import 'widgets/pay_password_prompt.dart';

export 'widgets/pay_password_prompt.dart' show PayMethodDisplay;

enum PayAuthMethod { manual, biometric }

class PayAuthResult {
  final bool success;
  final PayAuthMethod? method;
  final String? verifiedPayPin;

  const PayAuthResult({
    required this.success,
    this.method,
    this.verifiedPayPin,
  });

  static const cancelled = PayAuthResult(success: false);
}

/// Wallet backend is intentionally unavailable, but the complete 99chat
/// manual payment-confirmation UI remains reachable.  The caller owns the
/// final submit callback and returns the unavailable error there.
class PayAuthHelper {
  PayAuthHelper._();

  static Future<PayAuthResult> collectAndSubmit({
    required BuildContext context,
    required String title,
    required String amountText,
    String? amountCoin,
    required String payText,
    String? payCoinCode,
    String? payLogoUrl,
    required Future<String?> Function(String pwd) onSubmit,
    String? receiverName,
    String? receiverId,
    String? receiverAvatar,
    String? walletSubtitle,
    Future<PayMethodDisplay?> Function()? onChangePayMethod,
    bool tryBiometricFirst = true,
  }) async {
    String? verifiedPin;
    final ok = await PayPasswordPrompt.show(
      context,
      title: title,
      amountText: amountText,
      amountCoin: amountCoin,
      payText: payText,
      payCoinCode: payCoinCode,
      payLogoUrl: payLogoUrl,
      receiverName: receiverName,
      receiverId: receiverId,
      receiverAvatar: receiverAvatar,
      walletSubtitle: walletSubtitle,
      onChangePayMethod: onChangePayMethod,
      onSubmit: (pwd) async {
        final error = await onSubmit(pwd);
        if (error == null || error.isEmpty) verifiedPin = pwd;
        return error;
      },
    );
    if (!context.mounted || ok != true) return PayAuthResult.cancelled;
    return PayAuthResult(
      success: true,
      method: PayAuthMethod.manual,
      verifiedPayPin: verifiedPin,
    );
  }
}
