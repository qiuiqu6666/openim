import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/wallet_controller.dart';

void main() {
  test('balance visibility toggle matches 99chat semantics', () {
    final controller = WalletController();
    expect(controller.showBal, isTrue);
    controller.toggleBal();
    expect(controller.showBal, isFalse);
    controller.toggleBal();
    expect(controller.showBal, isTrue);
    controller.dispose();
  });

  test('unavailable backend keeps product shell without fake balances', () async {
    final controller = WalletController();
    await controller.load();

    expect(controller.loadFailed, isTrue);
    expect(controller.totalBal, '--');
    expect(controller.totalBalUsd, isEmpty);
    expect(controller.trxAddr, isEmpty);

    expect(controller.coins, hasLength(2));
    expect(controller.coins.map((e) => e.name), containsAll(<String>['99币', 'USDT']));
    for (final coin in controller.coins) {
      expect(coin.bal, '--');
      expect(coin.fiat, '--');
      expect(coin.balMinor, 0);
    }
    controller.dispose();
  });
}
