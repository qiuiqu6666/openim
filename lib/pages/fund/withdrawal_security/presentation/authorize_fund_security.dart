import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../services/fund_api.dart';
import '../../widgets/fund_page_colors.dart';
import '../data/fund_security_api.dart';
import '../data/fund_security_models.dart';
import '../data/fund_security_request.dart';
import 'fund_security_code_sheet.dart';
import 'fund_security_feedback.dart';

/// Call after recovering any existing order and freezing its business fields.
/// The final write consumes the SMS proof; this helper never submits a payment.
Future<FundSecurityProof?> authorizeFundSecurity(
  BuildContext context, {
  required FundSecurityRequest request,
  required FundApi api,
  required bool Function() isCurrent,
}) async {
  if (!context.mounted || !isCurrent()) return null;
  final security = FundWithdrawalSecurityApi(api);
  late FundSecurityCheck check;
  try {
    check = await security.check(request);
  } catch (error) {
    if (context.mounted && isCurrent()) {
      await showFundSecurityFailure(context, error, isCurrent: isCurrent);
    }
    return null;
  }
  if (!context.mounted || !isCurrent()) return null;
  if (check.blockedUntil > 0) {
    final colors = FundPageColors.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.card,
        title: Text('暂时无法转出', style: TextStyle(color: colors.text)),
        content: Text(
          '手机号或密码变更后需等待24小时。\n允许转出时间：${fundSecurityAllowedTime(check.blockedUntil)}',
          style: TextStyle(color: colors.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了')),
        ],
      ),
    );
    return null;
  }
  if (!check.smsRequired) return const FundSecurityProof();
  if (check.phoneMasked.trim().isEmpty) {
    await showFundSecurityFailure(
        context, const FundApiException(20038, 'Phone binding required'),
        isCurrent: isCurrent);
    return null;
  }
  final result = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: FundPageColors.of(context).card,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTokens.rLg))),
    builder: (_) => FundSecurityCodeSheet(
        request: request,
        security: security,
        phoneMasked: check.phoneMasked,
        isCurrent: isCurrent),
  );
  if (!context.mounted || !isCurrent()) return null;
  if (result is FundSecuritySheetFailure) {
    await showFundSecurityFailure(context, result.error, isCurrent: isCurrent);
    return null;
  }
  return result is FundSecurityProof ? result : null;
}
