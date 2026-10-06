import 'package:flutter/material.dart';

import 'record/wallet_record_screen.dart';
import 'wallet_repository.dart';

/// Existing routes share the fund history module and its source limits.
class WalletDepositRecordScreen extends StatelessWidget {
  const WalletDepositRecordScreen({super.key, this.repository});
  final WalletRepository? repository;
  @override
  Widget build(BuildContext context) =>
      WalletRecordScreen(depositsOnly: true, repository: repository);
}

class WalletWithdrawRecordScreen extends StatelessWidget {
  const WalletWithdrawRecordScreen({super.key, this.repository});
  final WalletRepository? repository;
  @override
  Widget build(BuildContext context) =>
      WalletRecordScreen(withdrawalsOnly: true, repository: repository);
}
