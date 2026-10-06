import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/widgets/payment/password_payment_sheet.dart';
import 'package:openim/widgets/payment/trade_password_keypad.dart';

const _password = ValueKey('payment-password');
const _confirm = ValueKey('payment-confirm');
const _sheet = ValueKey('payment-sheet');
const _cancel = ValueKey('payment-cancel');
const _passwordRegion = ValueKey('payment-password-region');
const _keypadRegion = ValueKey('payment-keypad-region');
const _summary = ValueKey('membership-summary');
const _entering = ValueKey('pay-state-enteringPassword');
const _processing = ValueKey('pay-state-processing');
const _success = ValueKey('pay-state-success');

class _Routes extends NavigatorObserver {
  Route<dynamic>? payment;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalBottomSheetRoute) payment = route;
  }
}

/// A second business deliberately returns a plain String rather than FundOrder.
class _MembershipPayment {
  _MembershipPayment({
    required this.onPay,
    this.onSuccess,
    this.onChangePaymentMethod,
    this.summaryBuilder,
    this.successDuration = const Duration(milliseconds: 900),
  });

  final Future<String> Function(String) onPay;
  final FutureOr<void> Function(String)? onSuccess;
  final Future<bool> Function()? onChangePaymentMethod;
  final PaymentSummaryBuilder? summaryBuilder;
  final Duration successDuration;
  final navigator = GlobalKey<NavigatorState>();
  final routes = _Routes();
  final results = <String?>[];
  final errors = <String>[];

  Widget host({bool dark = false, double textScale = 1}) => MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [routes],
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(top: 24, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open-membership-payment'),
                onPressed: () async {
                  final result = await showPasswordPaymentSheet<String>(
                    context: context,
                    builder: (_) => PasswordPaymentSheet<String>(
                      title: 'Membership',
                      summary: const SizedBox(
                        key: _summary,
                        height: 64,
                        child: Center(child: Text('12.000001 USDT')),
                      ),
                      summaryBuilder: summaryBuilder,
                      onChangePaymentMethod: onChangePaymentMethod,
                      onPay: onPay,
                      errorMessage: (error) => 'Rejected: $error',
                      onError: errors.add,
                      onSuccess: onSuccess,
                      successDisplayDuration: successDuration,
                    ),
                  );
                  results.add(result);
                },
                child: const Text('Open membership payment'),
              ),
            ),
          ),
        ),
      );
}

Future<void> _open(WidgetTester tester, _MembershipPayment payment,
    {bool dark = false,
    double scale = 1,
    Size size = const Size(375, 812)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(payment.host(dark: dark, textScale: scale));
  await tester.tap(find.byKey(const ValueKey('open-membership-payment')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Map<String, Rect> _geometry(WidgetTester tester) => {
      'sheet': tester.getRect(find.byKey(_sheet)),
      'title': tester.getRect(find.text('Membership')),
      'summary': tester.getRect(find.byKey(_summary)),
      'password': tester.getRect(find.byKey(_passwordRegion)),
      'keypad': tester.getRect(find.byKey(_keypadRegion)),
    };

void _sameGeometry(WidgetTester tester, Map<String, Rect> original) {
  final actual = _geometry(tester);
  for (final entry in original.entries) {
    expect(actual[entry.key], entry.value,
        reason: '${entry.key} must not jump');
  }
}

Future<void> _digits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.byKey(ValueKey('trade-password-key-$digit')));
    await tester.pump();
  }
}

Future<void> _denyDismissal(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
  await tester.tapAt(const Offset(4, 4));
  await tester.pump();
  await tester.dragFrom(
      tester.getTopLeft(find.byKey(_sheet)) + const Offset(30, 16),
      const Offset(0, 180));
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byKey(_sheet), findsOneWidget);
}

void main() {
  for (final changed in [false, true]) {
    testWidgets(
        'method selection is serialized and resets PIN only on change=$changed',
        (tester) async {
      final selection = Completer<bool>();
      var calls = 0;
      var payments = 0;
      final payment = _MembershipPayment(
        onPay: (_) async {
          payments++;
          return 'unused';
        },
        onChangePaymentMethod: () {
          calls++;
          return selection.future;
        },
        summaryBuilder: (_, change) => SizedBox(
          key: _summary,
          height: 64,
          child: TextButton(
            key: const ValueKey('change-membership-method'),
            onPressed: change,
            child: const Text('Change payment method'),
          ),
        ),
      );
      await _open(tester, payment);
      await _digits(tester, '123');
      final original = _geometry(tester);
      final change = tester
          .widget<TextButton>(
              find.byKey(const ValueKey('change-membership-method')))
          .onPressed!;
      change();
      change();
      await tester.pump();
      expect(calls, 1);
      expect(tester.widget<TextField>(find.byKey(_password)).enabled, isFalse);
      expect(
          tester
              .widget<TradePasswordKeyPad>(find.byType(TradePasswordKeyPad))
              .enabled,
          isFalse);
      _sameGeometry(tester, original);
      if (changed) {
        tester.widget<TextField>(find.byKey(_password)).controller!.text =
            '123456';
        await tester.pump();
        expect(payments, 0);
      }
      selection.complete(changed);
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(_password)).enabled, isTrue);
      expect(tester.widget<TextField>(find.byKey(_password)).controller!.text,
          changed ? '' : '123');
      expect(payments, 0);
      expect(find.byKey(_processing), findsNothing);
      _sameGeometry(tester, original);
      await tester.tap(find.byKey(_cancel));
      await tester.pumpAndSettle();
      expect(payment.results, [null]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late method selection cannot update a disposed payment sheet',
      (tester) async {
    final selection = Completer<bool>();
    final payment = _MembershipPayment(
      onPay: (_) async => 'unused',
      onChangePaymentMethod: () => selection.future,
      summaryBuilder: (_, change) => SizedBox(
        key: _summary,
        height: 64,
        child:
            TextButton(onPressed: change, child: const Text('Change method')),
      ),
    );
    await _open(tester, payment);
    await tester.tap(find.text('Change method'));
    await tester.pump();
    payment.navigator.currentState!.removeRoute(payment.routes.payment!);
    await tester.pumpAndSettle();
    selection.complete(true);
    await tester.pump();
    expect(find.byKey(_sheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delayed membership payment locks input and returns its result',
      (tester) async {
    final completer = Completer<String>();
    final passwords = <String>[];
    final succeeded = <String>[];
    final payment = _MembershipPayment(
      onPay: (password) {
        passwords.add(password);
        return completer.future;
      },
      onSuccess: succeeded.add,
    );
    await _open(tester, payment);
    expect(find.byKey(_entering), findsOneWidget);
    final original = _geometry(tester);
    expect(original['keypad']!.height, 216 + 34);
    await tester.enterText(find.byKey(_password), '123456');
    await tester.pump();
    expect(passwords, ['123456']);
    expect(find.byKey(_processing), findsOneWidget);
    final indicator = find.byType(CircularProgressIndicator);
    expect(tester.widget<CircularProgressIndicator>(indicator).value, isNull);
    expect(tester.getSize(indicator), const Size.square(30));
    expect(find.byType(TradePasswordKeyPad), findsNothing);
    final lockedInput = tester.widget<TextField>(find.byKey(_password));
    expect(lockedInput.enabled, isFalse);
    expect(lockedInput.readOnly, isTrue);
    _sameGeometry(tester, original);
    await _denyDismissal(tester);
    completer.complete('membership-order-7');
    await tester.pump();
    expect(find.byKey(_success), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(succeeded, ['membership-order-7']);
    _sameGeometry(tester, original);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byKey(_success), findsOneWidget);
    expect(payment.results, isEmpty);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 350));
    expect(payment.results, ['membership-order-7']);
    expect(passwords, hasLength(1));
    expect(find.byKey(_sheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel and system back return null before authorization',
      (tester) async {
    var requests = 0;
    final payment = _MembershipPayment(onPay: (_) async {
      requests++;
      return 'unused';
    });
    await _open(tester, payment);
    await tester.enterText(find.byKey(_password), '123');
    await tester.tap(find.byKey(_cancel));
    await tester.pumpAndSettle();
    expect(payment.results, [null]);
    expect(requests, 0);
    await tester.tap(find.byKey(const ValueKey('open-membership-payment')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(payment.results, [null, null]);
    expect(requests, 0);
  });

  testWidgets(
      'rejected payment reports its message clears PIN and allows retry',
      (tester) async {
    final first = Completer<String>(), second = Completer<String>();
    final passwords = <String>[];
    final payment = _MembershipPayment(onPay: (password) {
      passwords.add(password);
      return passwords.length == 1 ? first.future : second.future;
    });
    await _open(tester, payment);
    final original = _geometry(tester);
    await tester.enterText(find.byKey(_password), '111111');
    await tester.pump();
    first.completeError(StateError('wrong payment password'));
    await tester.pump();
    expect(find.byKey(_entering), findsOneWidget);
    expect(payment.errors.single, contains('wrong payment password'));
    expect(payment.results, isEmpty);
    expect(
        tester.widget<TextField>(find.byKey(_password)).controller!.text, '');
    _sameGeometry(tester, original);
    await _digits(tester, '222222');
    expect(passwords, ['111111', '222222']);
    second.complete('membership-retry-ok');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 350));
    expect(payment.results, ['membership-retry-ok']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-frame paste keypad and semantic submit authorize once',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final completer = Completer<String>();
      var requests = 0;
      final payment = _MembershipPayment(onPay: (_) {
        requests++;
        return completer.future;
      });
      await _open(tester, payment);
      final controller =
          tester.widget<TextField>(find.byKey(_password)).controller!;
      final node = tester.getSemantics(find.byKey(_confirm));
      final actions = node.getSemanticsData().customSemanticsActionIds;
      expect(actions, isNotEmpty);
      final keypad =
          tester.widget<TradePasswordKeyPad>(find.byType(TradePasswordKeyPad));
      controller.text = '123456';
      controller.text = '654321';
      keypad.onDigit('1');
      for (final id in actions!) {
        node.owner!.performAction(node.id, SemanticsAction.customAction, id);
      }
      await tester.pump();
      expect(requests, 1);
      expect(find.byKey(_processing), findsOneWidget);
      await _denyDismissal(tester);
      expect(requests, 1);
      completer.complete('single-authorization');
      await tester.pump();
      await _denyDismissal(tester);
      expect(find.byKey(_success), findsOneWidget);
      expect(requests, 1);
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump(const Duration(milliseconds: 350));
      expect(payment.results, ['single-authorization']);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'forced route removal ignores a late response and keeps newer route',
      (tester) async {
    final completer = Completer<String>();
    var callbacks = 0;
    final payment = _MembershipPayment(
      onPay: (_) => completer.future,
      onSuccess: (_) => callbacks++,
    );
    await _open(tester, payment);
    await tester.enterText(find.byKey(_password), '123456');
    await tester.pump();
    payment.navigator.currentState!.removeRoute(payment.routes.payment!);
    payment.navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('New unrelated route'))));
    await tester.pumpAndSettle();
    completer.complete('late-membership-order');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(callbacks, 0);
    expect(payment.results, [null]);
    expect(find.text('New unrelated route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final failure in [false, true]) {
    testWidgets(
        'response during a forced pop exit animation is ignored failure=$failure',
        (tester) async {
      final completer = Completer<String>();
      var successCallbacks = 0;
      final payment = _MembershipPayment(
        onPay: (_) => completer.future,
        onSuccess: (_) => successCallbacks++,
      );
      await _open(tester, payment);
      await tester.enterText(find.byKey(_password), '123456');
      await tester.pump();
      expect(find.byKey(_processing), findsOneWidget);
      payment.navigator.currentState!.pop();
      // Complete before a frame can finish the route's reverse transition;
      // mounted alone must not permit callbacks or an error notification.
      expect(find.byKey(_sheet), findsOneWidget);
      if (failure) {
        completer.completeError(StateError('late rejected password'));
      } else {
        completer.complete('late-paid-membership-order');
      }
      await tester.pump();
      expect(successCallbacks, 0);
      expect(payment.errors, isEmpty);
      expect(find.byKey(_success), findsNothing);
      await tester.pump(const Duration(milliseconds: 350));
      expect(payment.results, [null]);
      expect(find.byKey(_sheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('post-payment callback failure cannot unlock a committed payment',
      (tester) async {
    var requests = 0;
    final payment = _MembershipPayment(
      onPay: (_) async {
        requests++;
        return 'committed-membership-order';
      },
      onSuccess: (_) async => throw StateError('local receipt unavailable'),
      successDuration: const Duration(milliseconds: 200),
    );
    await _open(tester, payment);
    await tester.enterText(find.byKey(_password), '123456');
    await tester.pump();
    expect(find.byKey(_success), findsOneWidget);
    expect(find.byKey(_entering), findsNothing);
    expect(find.byType(TradePasswordKeyPad), findsNothing);
    await tester.pump(const Duration(milliseconds: 199));
    expect(payment.results, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 350));
    expect(payment.results, ['committed-membership-order']);
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'slow success refresh cannot delay closure or close a later route',
      (tester) async {
    final refresh = Completer<void>();
    var requests = 0;
    final receipts = <String>[];
    final payment = _MembershipPayment(
      onPay: (_) async {
        requests++;
        return 'committed-before-refresh';
      },
      onSuccess: (result) {
        receipts.add(result);
        return refresh.future;
      },
    );
    await _open(tester, payment);
    await tester.enterText(find.byKey(_password), '123456');
    await tester.pump();
    expect(find.byKey(_success), findsOneWidget);
    expect(receipts, ['committed-before-refresh']);
    await tester.pump(const Duration(milliseconds: 899));
    expect(find.byKey(_success), findsOneWidget);
    expect(payment.results, isEmpty);
    expect(refresh.isCompleted, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 350));
    expect(payment.results, ['committed-before-refresh']);
    expect(find.byKey(_sheet), findsNothing);
    expect(refresh.isCompleted, isFalse);
    expect(requests, 1);
    payment.navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Membership receipt page'))));
    await tester.pumpAndSettle();
    refresh.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(payment.results, ['committed-before-refresh']);
    expect(find.text('Membership receipt page'), findsOneWidget);
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'incomplete PIN can be deleted and scrim or drag never cancels it',
      (tester) async {
    final completer = Completer<String>();
    final passwords = <String>[];
    final payment = _MembershipPayment(onPay: (password) {
      passwords.add(password);
      return completer.future;
    });
    await _open(tester, payment);
    await _digits(tester, '12345');
    expect(passwords, isEmpty);
    await tester.tap(find.byKey(const ValueKey('trade-password-key-del')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(_password)).controller!.text,
        '1234');
    await tester.tapAt(const Offset(4, 4));
    await tester.dragFrom(
        tester.getTopLeft(find.byKey(_sheet)) + const Offset(30, 16),
        const Offset(0, 180));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(_entering), findsOneWidget);
    expect(payment.results, isEmpty);
    await _digits(tester, '56');
    expect(passwords, ['123456']);
    completer.complete('deleted-and-reentered');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 350));
    expect(payment.results, ['deleted-and-reentered']);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final size in [const Size(320, 812), const Size(812, 375)]) {
      testWidgets('stable payment frame at $size dark=$dark with large text',
          (tester) async {
        final completer = Completer<String>();
        final payment = _MembershipPayment(onPay: (_) => completer.future);
        await _open(tester, payment, dark: dark, scale: 2, size: size);
        expect(find.text('Membership'), findsOneWidget);
        expect(find.text('12.000001 USDT'), findsOneWidget);
        final original = _geometry(tester);
        expect(original['keypad']!.height, 250);
        expect(original['keypad']!.bottom, lessThanOrEqualTo(size.height));
        expect(original['sheet']!.left, greaterThanOrEqualTo(0));
        expect(original['sheet']!.right, lessThanOrEqualTo(size.width));
        await tester.enterText(find.byKey(_password), '123456');
        await tester.pump();
        _sameGeometry(tester, original);
        completer.complete('large-font-order');
        await tester.pump();
        _sameGeometry(tester, original);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 1300));
        await tester.pump(const Duration(milliseconds: 350));
        expect(payment.results, ['large-font-order']);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
