import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/trade_password_page.dart';

import 'support/wallet_entry_fixture.dart';

void main() {
  testWidgets('a current password permits each new entry after a fresh check',
      (tester) async {
    final settings = WalletEntrySettings();
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    expect(await fixture.enter(), isTrue);
    expect(fixture.allowed, ['wallet']);
    expect(settings.checks, 1);
    expect(find.byType(TradePasswordPage), findsNothing);
    expect(await fixture.enter('profile'), isTrue);
    expect(settings.checks, 2);
    expect(fixture.allowed, ['wallet', 'profile']);
  });

  testWidgets('an unset password opens real setup above the nested navigator',
      (tester) async {
    final settings = WalletEntrySettings()..ready = false;
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester, nested: true);
    final pending = fixture.enter();
    await tester.pumpAndSettle();
    expect(find.byType(TradePasswordPage), findsOneWidget);
    expect(fixture.rootNavigator.currentState!.canPop(), isTrue);
    expect(fixture.nestedNavigator.currentState!.canPop(), isFalse);
    expect(fixture.allowed, isEmpty);
    await enterPaymentPin(tester);
    expect(find.text('请再次输入交易密码'), findsOneWidget);
    expect(settings.submitted, isEmpty);
    await enterPaymentPin(tester);
    expect(await pending, isTrue);
    expect(settings.events, ['check', 'save', 'check']);
    expect(settings.submitted, ['123456']);
    expect(fixture.allowed, ['wallet']);
    expect(find.byType(TradePasswordPage), findsNothing);
    await dismissEntryTip(tester);
  });

  testWidgets('canceling setup keeps the original page without a second check',
      (tester) async {
    final settings = WalletEntrySettings()..ready = false;
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final pending = fixture.enter();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
    expect(settings.events, ['check']);
    expect(fixture.allowed, isEmpty);
    expect(find.byKey(const ValueKey('entry-wallet-tab')), findsOneWidget);
  });

  testWidgets('a failed save never admits the wallet and can be retried',
      (tester) async {
    final settings = WalletEntrySettings()
      ..ready = false
      ..saveError = StateError('offline');
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final pending = fixture.enter();
    await tester.pumpAndSettle();
    await enterPaymentPin(tester);
    await enterPaymentPin(tester);
    expect(find.byType(TradePasswordPage), findsOneWidget);
    expect(find.text('设置失败，请稍后重试'), findsOneWidget);
    expect(fixture.allowed, isEmpty);
    expect(settings.events, ['check', 'save']);
    settings.saveError = null;
    await enterPaymentPin(tester);
    expect(await pending, isTrue);
    expect(settings.events, ['check', 'save', 'save', 'check']);
    expect(fixture.allowed, ['wallet']);
    await dismissEntryTip(tester);
  });

  testWidgets('a successful save must also be confirmed by backend status',
      (tester) async {
    final settings = WalletEntrySettings()
      ..ready = false
      ..readyAfterSave = false;
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final pending = fixture.enter();
    await tester.pumpAndSettle();
    await enterPaymentPin(tester);
    await enterPaymentPin(tester);
    expect(await pending, isFalse);
    expect(settings.events, ['check', 'save', 'check']);
    expect(fixture.allowed, isEmpty);
    expect(find.text('支付密码尚未生效，请重新设置后再试'), findsOneWidget);
    await dismissEntryTip(tester);
  });

  testWidgets('repeated pending entry starts only one check and one setup',
      (tester) async {
    final status = Completer<bool>();
    final settings = WalletEntrySettings()..check = (_) => status.future;
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final first = fixture.enter();
    expect(await fixture.enter('profile'), isFalse);
    expect(settings.checks, 1);
    status.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(TradePasswordPage), findsOneWidget);
    expect(await fixture.enter('profile'), isFalse);
    expect(settings.checks, 1);
    fixture.rootNavigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(await first, isFalse);
    expect(fixture.allowed, isEmpty);
  });

  testWidgets('other tab invalidates a late status and permits a new entry',
      (tester) async {
    final status = Completer<bool>();
    final settings = WalletEntrySettings()..check = (_) => status.future;
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final first = fixture.enter();
    await tester.tap(find.byKey(const ValueKey('entry-other-tab')));
    status.complete(false);
    await tester.pumpAndSettle();
    expect(await first, isFalse);
    expect(find.byType(TradePasswordPage), findsNothing);
    fixture.active = true;
    settings.check = (_) async => true;
    expect(await fixture.enter(), isTrue);
    expect(settings.checks, 2);
    expect(fixture.allowed, ['wallet']);
  });

  testWidgets('cancel cannot let an old response erase a newer pending entry',
      (tester) async {
    final oldStatus = Completer<bool>();
    final newStatus = Completer<bool>();
    final settings = WalletEntrySettings()
      ..check = (count) => count == 1 ? oldStatus.future : newStatus.future;
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final oldEntry = fixture.enter();
    fixture.coordinator.cancel();
    final newEntry = fixture.enter('profile');
    oldStatus.complete(true);
    await tester.pump();
    expect(await oldEntry, isFalse);
    expect(await fixture.enter(), isFalse);
    expect(settings.checks, 2);
    newStatus.complete(true);
    await tester.pump();
    expect(await newEntry, isTrue);
    expect(fixture.allowed, ['profile']);
  });

  testWidgets('switching session invalidates an in-flight status response',
      (tester) async {
    final status = Completer<bool>();
    final settings = WalletEntrySettings()..check = (_) => status.future;
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final pending = fixture.enter();
    fixture.session = 'other-user:token-b';
    status.complete(false);
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
    expect(fixture.allowed, isEmpty);
    expect(find.byType(TradePasswordPage), findsNothing);
  });

  testWidgets('an old setup page cannot save after the login session changes',
      (tester) async {
    final settings = WalletEntrySettings()..ready = false;
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final pending = fixture.enter();
    await tester.pumpAndSettle();
    await enterPaymentPin(tester);
    fixture.session = 'other-user:token-b';
    await enterPaymentPin(tester);
    expect(settings.submitted, isEmpty);
    expect(fixture.allowed, isEmpty);
    expect(find.byType(TradePasswordPage), findsOneWidget);
    fixture.rootNavigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
    expect(settings.checks, 1);
  });

  testWidgets('closing the owner ignores late status without navigation',
      (tester) async {
    final status = Completer<bool>();
    final settings = WalletEntrySettings()..check = (_) => status.future;
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final pending = fixture.enter();
    await tester.pumpWidget(const SizedBox.shrink());
    status.complete(false);
    await tester.pump();
    expect(await pending, isFalse);
    expect(fixture.allowed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose makes late and future entries inert', (tester) async {
    final status = Completer<bool>();
    final settings = WalletEntrySettings()..check = (_) => status.future;
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final pending = fixture.enter();
    fixture.coordinator.dispose();
    status.complete(true);
    await tester.pump();
    expect(await pending, isFalse);
    expect(await fixture.enter(), isFalse);
    expect(settings.checks, 1);
    expect(fixture.allowed, isEmpty);
  });

  testWidgets('covered owner rejects a late response without opening setup',
      (tester) async {
    final status = Completer<bool>();
    final settings = WalletEntrySettings()..check = (_) => status.future;
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final pending = fixture.enter();
    unawaited(fixture.rootNavigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Other page')),
    )));
    await tester.pumpAndSettle();
    status.complete(false);
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
    expect(find.text('Other page'), findsOneWidget);
    expect(find.byType(TradePasswordPage), findsNothing);
    expect(fixture.allowed, isEmpty);
  });

  testWidgets('inactive entry does not request backend status', (tester) async {
    final settings = WalletEntrySettings();
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    fixture.active = false;
    expect(await fixture.enter(), isFalse);
    expect(settings.checks, 0);
    expect(fixture.allowed, isEmpty);
  });

  testWidgets('leaving the foreground invalidates a pending response',
      (tester) async {
    final status = Completer<bool>();
    final settings = WalletEntrySettings()..check = (_) => status.future;
    final fixture = WalletEntryFixture(settings);
    await fixture.mount(tester);
    final pending = fixture.enter();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    status.complete(true);
    await tester.pump();
    expect(await pending, isFalse);
    expect(fixture.allowed, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  final errors = <Locale, String>{
    const Locale('zh', 'CN'): '无法确认支付密码状态，请稍后重试',
    const Locale('zh', 'TW'): '無法確認支付密碼狀態，請稍後重試',
    const Locale('en', 'US'):
        'Could not check your payment password. Please try again.',
    const Locale('ja', 'JP'): '支払いパスワードの状態を確認できません。再度お試しください。',
    const Locale('ko', 'KR'): '결제 비밀번호 상태를 확인할 수 없습니다. 다시 시도해 주세요.',
  };
  for (final entry in errors.entries) {
    testWidgets('status failure uses the shared tip in ${entry.key}',
        (tester) async {
      final settings = WalletEntrySettings()
        ..check = (_) async => throw StateError('backend unavailable');
      final fixture = WalletEntryFixture(settings);
      await fixture.mount(tester, locale: entry.key);
      expect(await fixture.enter(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(fixture.allowed, isEmpty);
      expect(find.byType(TradePasswordPage), findsNothing);
      await dismissEntryTip(tester);
    });
  }
}
