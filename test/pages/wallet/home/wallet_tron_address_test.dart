import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:openim/pages/wallet/home/wallet_home_view.dart';
import 'package:openim/pages/wallet/home/tron_address/wallet_tron_address_source.dart';
import 'package:openim/pages/wallet/wallet_controller.dart';
import 'package:openim/pages/wallet/widgets/wallet_coin_logo.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';

import 'wallet_home_test_support.dart';

void main() {
  test('pending address never blocks balances or gets overwritten by snapshot',
      () async {
    final source = _AddressRepository();
    final controller = WalletController(repo: source);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.totalBal, walletHomeFixture.totalBal);
    expect(controller.addressLoading, isTrue);
    source.result.complete('TRealAddressFromDepositEndpoint');
    await Future<void>.delayed(Duration.zero);
    expect(controller.trxAddr, 'TRealAddressFromDepositEndpoint');
    await controller.load();
    expect(controller.trxAddr, 'TRealAddressFromDepositEndpoint');
  });

  test('address request failure preserves loaded balances', () async {
    final source = _AddressRepository();
    final controller = WalletController(repo: source);
    addTearDown(controller.dispose);
    await controller.load();
    source.result.completeError(StateError('offline'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.addressFailed, isTrue);
    expect(controller.loadFailed, isFalse);
    expect(controller.trxAddr, isEmpty);
    expect(controller.totalBal, walletHomeFixture.totalBal);
  });
  testWidgets('USDT address sits above assets and copies the full value',
      (tester) async {
    final controller = await loadedHomeController();
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpWalletHome(tester,
        controller: controller,
        page: Builder(
            builder: (context) => EasyLoading.init()(
                context, const Scaffold(body: WalletHomeView()))));
    await tester.pumpAndSettle();
    expect(find.text(walletHomeFixture.trxAddr), findsOneWidget);
    final usdtLogos = tester
        .widgetList<WalletCoinLogo>(find.byType(WalletCoinLogo))
        .where((logo) => logo.type == CoinType.usdt);
    expect(usdtLogos.length, 2,
        reason: 'Address and asset list must use the same shared coin artwork');
    final addressRect = tester.getRect(walletHomeKey('wallet-tron-address'));
    expect(
        addressRect.top,
        greaterThan(
            tester.getRect(walletHomeKey('wallet-action-swap')).bottom));
    expect(addressRect.bottom,
        lessThan(tester.getRect(walletHomeKey('wallet-assets-section')).top));
    await tester.tap(walletHomeKey('wallet-tron-address-copy'));
    await tester.pump();
    expect(copied, walletHomeFixture.trxAddr);
    await EasyLoading.dismiss(animation: false);
    await tester.pumpAndSettle();
  });

  for (final brightness in Brightness.values) {
    testWidgets('TRON row supports small screens and large text in $brightness',
        (tester) async {
      final controller = await loadedHomeController();
      await pumpWalletHome(tester,
          controller: controller,
          size: const Size(320, 844),
          brightness: brightness,
          textScale: 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(walletHomeKey('wallet-tron-address-copy')).height,
          greaterThanOrEqualTo(48));
    });
  }
}

class _AddressRepository extends HomeTestRepository
    implements WalletTronAddressSource {
  final result = Completer<String>();
  @override
  Future<String> getTronAddress() => result.future;
}
