import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/deposit/widgets/wallet_deposit_address_card.dart';
import 'package:openim/pages/wallet/deposit/widgets/wallet_deposit_share_preview.dart';
import 'package:openim/pages/wallet/wallet_share_service.dart';

import 'support/wallet_deposit_qr_expectation.dart';
import 'support/wallet_deposit_test_support.dart';

void main() {
  testWidgets(
      'saving exports the static QR and complete real address without card actions',
      (tester) async {
    final service = DepositTestShareService();
    await pumpWalletDeposit(tester, api: WalletTestFundApi(), share: service);
    await _openShare(tester);
    final preview = find.byType(WalletDepositSharePreview);
    expect(preview, findsOneWidget);
    expect(
        find.descendant(
            of: preview, matching: find.byType(WalletDepositAddressCard)),
        findsNothing);
    expect(tester.widget<Text>(depositKey('wallet-deposit-share-address')).data,
        testDepositAddress);
    for (final action in [
      'wallet-deposit-copy',
      'wallet-deposit-save',
      'wallet-deposit-contract-info',
      'wallet-deposit-address-copy'
    ]) {
      expect(find.descendant(of: preview, matching: depositKey(action)),
          findsNothing);
    }
    await tester.ensureVisible(depositKey('wallet-deposit-save'));
    await tester.tap(depositKey('wallet-deposit-save'));
    await _settleToast(tester);
    expect(service.saves, hasLength(1));
    final boundary = find.byKey(service.saves.single);
    expect(find.descendant(of: boundary, matching: preview), findsOneWidget);
    final qr = find.descendant(
        of: boundary, matching: depositKey('wallet-deposit-qr'));
    expect(await decodeDepositRenderedQr(tester, service.saves.single, qr),
        testDepositAddress);
    expect(find.text('图片已保存'), findsOneWidget);
    final toastCenter = tester.getCenter(find.text('图片已保存'));
    expect(toastCenter.dx, closeTo(390 / 2, 1));
    expect(toastCenter.dy, closeTo(844 / 2, 1));
    await EasyLoading.dismiss(animation: false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('repeated save taps remain singleflight and preserve the address',
      (tester) async {
    final pending = Completer<WalletSaveImgResult>();
    final service = DepositTestShareService()
      ..saveResponse = (_, __) => pending.future;
    await pumpWalletDeposit(tester, api: WalletTestFundApi(), share: service);
    await _openShare(tester);
    await tester.ensureVisible(depositKey('wallet-deposit-save'));
    await tester.tap(depositKey('wallet-deposit-save'));
    await tester.tap(depositKey('wallet-deposit-save'));
    await tester.pump();
    expect(service.saves, hasLength(1));
    expect(find.text('保存中'), findsOneWidget);
    pending.complete(WalletSaveImgResult.success);
    await _settleToast(tester);
    expect(find.text('图片已保存'), findsOneWidget);
    expect(tester.widget<Text>(depositKey('wallet-deposit-share-address')).data,
        testDepositAddress);
    await EasyLoading.dismiss(animation: false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'the sheet shares the complete image and offers only the two image actions',
      (tester) async {
    final service = DepositTestShareService();
    await pumpWalletDeposit(tester, api: WalletTestFundApi(), share: service);
    await _openShare(tester);
    final sheet = depositKey('wallet-deposit-share-sheet');
    for (final action in [
      'wallet-deposit-copy',
      'wallet-deposit-sms',
      'wallet-deposit-wechat',
      'wallet-deposit-qq',
    ]) {
      expect(find.descendant(of: sheet, matching: depositKey(action)),
          findsNothing);
    }
    await tester.tap(depositKey('wallet-deposit-system-share'));
    await tester.pumpAndSettle();
    expect(service.copies, isEmpty);
    expect(service.messages, isEmpty);
    expect(service.shares, isEmpty);
    expect(service.imageShares, hasLength(1));
    final boundary = find.byKey(service.imageShares.single);
    final qr = find.descendant(
        of: boundary, matching: depositKey('wallet-deposit-qr'));
    expect(
        await decodeDepositRenderedQr(tester, service.imageShares.single, qr),
        testDepositAddress);
    await EasyLoading.dismiss(animation: false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
    const Locale('ja'),
    const Locale('ko'),
  ]) {
    testWidgets(
        'save failure uses the current language once in ${language.languageCode}',
        (tester) async {
      final service = DepositTestShareService()
        ..saveResult = WalletSaveImgResult.permissionDenied;
      await pumpWalletDeposit(tester,
          api: WalletTestFundApi(), share: service, locale: language);
      await _openShare(tester);
      var shown = 0;
      void onStatus(EasyLoadingStatus status) {
        if (status == EasyLoadingStatus.show) shown++;
      }

      EasyLoading.addStatusCallback(onStatus);
      addTearDown(() => EasyLoading.removeCallback(onStatus));
      await tester.ensureVisible(depositKey('wallet-deposit-save'));
      await tester.tap(depositKey('wallet-deposit-save'));
      await _settleToast(tester);
      final message = switch (language.languageCode) {
        'en' => 'Image was not saved. Check photo access and retry.',
        'ja' => '画像を保存できませんでした。写真のアクセス権を確認してください。',
        'ko' => '이미지를 저장하지 못했습니다. 사진 접근 권한을 확인하세요.',
        _ => language.countryCode == 'TW'
            ? '圖片未儲存，請檢查相簿權限後重試'
            : '图片未保存，请检查相册权限后重试',
      };
      expect(find.text(message), findsOneWidget);
      expect(shown, 1);
      expect(service.saves, hasLength(1));
      expect(find.text('图片已保存'), findsNothing);
      await EasyLoading.dismiss(animation: false);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'pending image share blocks duplicate actions and ignores late errors',
      (tester) async {
    final pending = Completer<WalletSystemShareResult>();
    final service = DepositTestShareService()
      ..shareResponse = (_, __) => pending.future;
    await pumpWalletDeposit(tester, api: WalletTestFundApi(), share: service);
    await _openShare(tester);
    await tester.tap(depositKey('wallet-deposit-system-share'));
    await tester.tap(depositKey('wallet-deposit-system-share'));
    await tester.pump();
    expect(service.imageShares, hasLength(1));
    expect(find.text('分享中'), findsOneWidget);
    expect(tester.widget<InkWell>(depositKey('wallet-deposit-save')).onTap,
        isNull);
    expect(
        tester.widget<InkWell>(depositKey('wallet-deposit-system-share')).onTap,
        isNull);
    await tester.tap(depositKey('wallet-deposit-share-cancel'));
    await tester.pumpAndSettle();
    pending.complete(WalletSystemShareResult.failed);
    await _settleToast(tester);
    expect(depositKey('wallet-deposit-share-sheet'), findsNothing);
    expect(find.text('分享失败，请重试'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dismissed native sharing restores the actions without an error',
      (tester) async {
    final service = DepositTestShareService()
      ..shareResult = WalletSystemShareResult.dismissed;
    await pumpWalletDeposit(tester, api: WalletTestFundApi(), share: service);
    await _openShare(tester);
    await tester.tap(depositKey('wallet-deposit-system-share'));
    await _settleToast(tester);
    expect(service.imageShares, hasLength(1));
    expect(find.text('分享中'), findsNothing);
    expect(find.text('分享失败，请重试'), findsNothing);
    expect(tester.widget<InkWell>(depositKey('wallet-deposit-save')).onTap,
        isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'account change blocks share and discards a late save notification',
      (tester) async {
    var account = 'server:first-user';
    final pending = Completer<WalletSaveImgResult>();
    final service = DepositTestShareService()
      ..saveResponse = (_, __) => pending.future;
    await pumpWalletDeposit(tester,
        api: WalletTestFundApi(),
        accountProvider: () => account,
        share: service);
    await _openShare(tester);
    await tester.ensureVisible(depositKey('wallet-deposit-save'));
    await tester.tap(depositKey('wallet-deposit-save'));
    await tester.pump();
    expect(service.saves, hasLength(1));
    account = 'server:second-user';
    pending.complete(WalletSaveImgResult.success);
    await tester.pumpAndSettle();
    expect(find.text('图片已保存'), findsNothing);
    for (final action in [
      'wallet-deposit-copy',
      'wallet-deposit-system-share'
    ]) {
      final target = find.descendant(
          of: depositKey('wallet-deposit-share-sheet'),
          matching: depositKey(action));
      if (target.evaluate().isNotEmpty) {
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pump();
      }
    }
    expect(service.copies, isEmpty);
    expect(service.shares, isEmpty);
    expect(service.imageShares, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('closing the share page ignores a late gallery result',
      (tester) async {
    final pending = Completer<WalletSaveImgResult>();
    final service = DepositTestShareService()
      ..saveResponse = (_, __) => pending.future;
    await pumpWalletDeposit(tester, api: WalletTestFundApi(), share: service);
    await _openShare(tester);
    await tester.ensureVisible(depositKey('wallet-deposit-save'));
    await tester.tap(depositKey('wallet-deposit-save'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(WalletSaveImgResult.success);
    await tester.pumpAndSettle();
    expect(find.text('图片已保存'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openShare(WidgetTester tester) async {
  await tester.ensureVisible(depositKey('wallet-deposit-share'));
  await tester.tap(depositKey('wallet-deposit-share'));
  await tester.pumpAndSettle();
  expect(depositKey('wallet-deposit-share-sheet'), findsOneWidget);
}

Future<void> _settleToast(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}
