import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/wallet/deposit/share/wallet_deposit_save_once.dart';
import 'package:openim/pages/wallet/wallet_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('coalesces concurrent saves and persists receipt across instances',
      () async {
    final saver = WalletDepositSaveOnce();
    final pending = Completer<WalletSaveImgResult>();
    var writes = 0;
    Future<WalletSaveImgResult> write() {
      writes++;
      return pending.future;
    }

    final first = saver.save(
        currency: 'USDT', network: 'TRON', address: 'a', write: write);
    final second = saver.save(
        currency: 'USDT', network: 'TRON', address: 'a', write: write);
    pending.complete(WalletSaveImgResult.success);
    expect(await first, DepositSaveResult.saved);
    await second;
    expect(writes, 1);
    expect(
        await WalletDepositSaveOnce().save(
            currency: 'USDT', network: 'TRON', address: 'a', write: write),
        DepositSaveResult.alreadySaved);
    expect(writes, 1);
    expect(
        await saver.save(
            currency: 'USDT', network: 'TRON', address: 'b', write: write),
        DepositSaveResult.saved);
    expect(writes, 2);
  });

  test('permission failure and exceptions allow retry', () async {
    final saver = WalletDepositSaveOnce();
    Future<DepositSaveResult> save(
            Future<WalletSaveImgResult> Function() write) =>
        saver.save(
            currency: 'USDT', network: 'TRON', address: 'a', write: write);
    expect(await save(() async => WalletSaveImgResult.permissionDenied),
        DepositSaveResult.failed);
    expect(await save(() async => throw StateError('save')),
        DepositSaveResult.failed);
    expect(await save(() async => WalletSaveImgResult.success),
        DepositSaveResult.saved);
  });
}
