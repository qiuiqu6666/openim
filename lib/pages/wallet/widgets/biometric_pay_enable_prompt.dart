import 'package:flutter/material.dart';
import '../pay_auth_helper.dart';

class BiometricPayEnablePrompt {
  BiometricPayEnablePrompt._();
  static Future<void> maybeShowAfterPaySuccess(
    BuildContext context, {
    required PayAuthMethod authMethod,
    String? verifiedPayPin,
  }) async {}
}
