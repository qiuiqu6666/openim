import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/fund_api.dart';
import '../../fund/fund_send_page.dart';
import '../../fund/payment/fund_payment_preferences.dart';
import '../data/wallet_operation_coordinator.dart';
import '../host/wallet_navigation.dart';
import '../order/wallet_order_events.dart';
import '../widgets/wallet_tip.dart';

/// The formerly unavailable Wallet friend action reuses the connected transfer
/// page, its payment setup, durable order recovery and actual receiver user ID.
Future<void> openWalletFriendTransfer(
  BuildContext context, {
  required String userID,
  required String coinCode,
  String? name,
  String? faceURL,
}) async {
  final accountID = DataSp.userID ?? '';
  final serverURL = Config.appAuthUrl;
  final owner = WalletOrderEvents.currentAccountKey;
  if (accountID.isEmpty || userID.trim().isEmpty) return;
  try {
    final preferences =
        FundPaymentPreferences(accountID: accountID, serverURL: serverURL);
    await preferences.save(walletFundCurrency(coinCode));
    if (!context.mounted || WalletOrderEvents.currentAccountKey != owner) {
      return;
    }
    final order = await openWalletPage<FundOrder>(
      context,
      FundSendPage(
        isRedPacket: false,
        userID: userID,
        recipientName: name,
        recipientFaceURL: faceURL,
        paymentPreferences: preferences,
      ),
      activityPage: 'wallet_transfer',
    );
    if (order == null || WalletOrderEvents.currentAccountKey != owner) return;
    WalletOrderEvents.notifyBalance(accountKey: owner);
    WalletOrderEvents.notifyRecord(accountKey: owner);
  } catch (error) {
    if (context.mounted && WalletOrderEvents.currentAccountKey == owner) {
      WalletTip.show(context, '暂时无法打开转账，请稍后重试');
    }
  }
}
