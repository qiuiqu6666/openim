import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/internal_transfer/data/fund_transfer_recipient_source.dart';
import 'package:openim/pages/fund/internal_transfer/presentation/fund_internal_transfer_form.dart';
import 'package:openim/pages/fund/widgets/fund_page_colors.dart';
import 'package:openim/services/fund_models.dart';
import 'package:openim_common/openim_common.dart';

const _previewDir =
    String.fromEnvironment('FUND_INTERNAL_TRANSFER_PREVIEW_DIR');

class _Fixture {
  final recipient = TextEditingController();
  final amount = TextEditingController();
  final focus = FocusNode();
  final formKey = GlobalKey<FormState>();
  int accountTaps = 0, contactTaps = 0, allTaps = 0, submits = 0;
  int areaCodeTaps = 0;
  int edited = 0, recipientEdited = 0, helpTaps = 0, historyTaps = 0;
  String? Function(String?)? recipientValidator;
  String? Function(String?)? amountValidator;

  void dispose() {
    recipient.dispose();
    amount.dispose();
    focus.dispose();
  }

  Widget page({
    FundCurrency currency = FundCurrency.usdt,
    FundTransferAccountType accountType = FundTransferAccountType.email,
    String phoneAreaCode = '+86',
    bool locked = false,
    bool loading = false,
    bool submitting = false,
    bool canSubmit = false,
    bool pending = false,
    String? error,
    String? recipientName,
    String available = '12.123456',
    String arrival = '0.00',
  }) =>
      FundInternalTransferForm(
          currency: currency,
          accountType: accountType,
          phoneAreaCode: phoneAreaCode,
          recipientInput: recipient,
          amount: amount,
          amountFocus: focus,
          formKey: formKey,
          isLocked: locked,
          isLoading: loading,
          isSubmitting: submitting,
          canSubmit: canSubmit,
          hasPending: pending,
          passwordSet: true,
          available: available,
          arrivalAmount: arrival,
          recipientName: recipientName,
          error: error,
          onEdited: () => edited++,
          onRecipientEdited: () => recipientEdited++,
          onChooseAccountType: () => accountTaps++,
          onChooseAreaCode: () => areaCodeTaps++,
          onChooseRecipient: () => contactTaps++,
          onAll: () {
            allTaps++;
            amount.text = available;
          },
          onSubmit: () => submits++,
          onReload: () {},
          onSetPassword: () {},
          onClose: () {},
          onHelp: () => helpTaps++,
          onHistory: () => historyTaps++,
          validateAmount: (value) => amountValidator?.call(value),
          validateRecipient: (value) => recipientValidator?.call(value));
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _pump(WidgetTester tester, Widget page,
    {Size size = const Size(375, 812),
    Brightness brightness = Brightness.light,
    double textScale = 1,
    EdgeInsets keyboard = EdgeInsets.zero,
    GlobalKey? boundaryKey}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  Styles.isDark = brightness == Brightness.dark;
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
              brightness: brightness,
              fontFamily: _previewDir.isEmpty ? null : 'FundPreviewCjk',
              colorScheme: ColorScheme.fromSeed(
                  seedColor: AppTokens.accent, brightness: brightness)),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  padding: const EdgeInsets.only(top: 24, bottom: 20),
                  viewInsets: keyboard),
              child: child!),
          home: RepaintBoundary(key: boundaryKey, child: page))));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    if (_previewDir.isEmpty) return;
    for (final font in [
      (name: 'FundPreviewCjk', path: 'C:/Windows/Fonts/msyh.ttc'),
      (
        name: 'MaterialIcons',
        path:
            'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
      ),
    ]) {
      final bytes = await File(font.path).readAsBytes();
      await (FontLoader(font.name)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final layout in const [
      (size: Size(375, 812), scale: 1.0),
      (size: Size(320, 640), scale: 2.0),
    ]) {
      testWidgets(
          'phone prefix is selectable and fits ${layout.size} ${layout.scale}x $brightness',
          (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final code = layout.scale == 2 ? '+1876' : '+1';
        await _pump(
            tester,
            fixture.page(
                accountType: FundTransferAccountType.phone,
                phoneAreaCode: code),
            brightness: brightness,
            size: layout.size,
            textScale: layout.scale);
        final prefix = _key('internal-transfer-area-code');
        expect(find.text(code), findsOneWidget);
        expect(find.text('请填写收款人手机号'), findsOneWidget);
        expect(tester.getSize(prefix).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(prefix);
        await tester.tap(prefix);
        await tester.enterText(
            _key('internal-transfer-recipient'), '13800138000');
        expect(fixture.areaCodeTaps, 1);
        expect(fixture.recipient.text, '13800138000');
        expect(fixture.recipientEdited, 1);
        expect(tester.takeException(), isNull);
      });
    }

    for (final layout in const [
      (size: Size(375, 812), scale: 1.0, keyboard: EdgeInsets.zero),
      (size: Size(320, 640), scale: 2.0, keyboard: EdgeInsets.zero),
      (size: Size(812, 375), scale: 2.0, keyboard: EdgeInsets.zero),
      (
        size: Size(375, 812),
        scale: 1.0,
        keyboard: EdgeInsets.only(bottom: 300)
      ),
    ]) {
      testWidgets(
          'internal withdrawal fits ${layout.size} ${layout.scale}x $brightness keyboard=${layout.keyboard.bottom}',
          (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        await _pump(tester, fixture.page(canSubmit: true),
            size: layout.size,
            brightness: brightness,
            textScale: layout.scale,
            keyboard: layout.keyboard);
        expect(_key('internal-transfer-form'), findsOneWidget);
        expect(find.text('提现 USDT'), findsOneWidget);
        final titleRect = tester.getRect(find.text('提现 USDT'));
        expect(titleRect.center.dx, closeTo(layout.size.width / 2, .01),
            reason: 'Two trailing actions must not pull the title off center.');
        final titleParagraph = tester.renderObject<RenderParagraph>(
            find.descendant(
                of: find.text('提现 USDT'), matching: find.byType(RichText)));
        expect(titleParagraph.didExceedMaxLines, isFalse);
        expect(tester.getSize(_key('fund-close')).width,
            greaterThanOrEqualTo(48));
        expect(tester.getSize(_key('fund-close')).height,
            greaterThanOrEqualTo(48));
        for (final action in ['help', 'history']) {
          final actionRect = tester.getRect(_key('internal-transfer-$action'));
          expect(titleRect.overlaps(actionRect), isFalse);
          expect(actionRect.width, greaterThanOrEqualTo(48));
          expect(actionRect.height, greaterThanOrEqualTo(48));
        }
        expect(find.text('--'), findsNothing);
        expect(tester.takeException(), isNull);
        final submit = _key('internal-transfer-submit');
        await tester.scrollUntilVisible(submit, 180,
            scrollable: find
                .descendant(
                    of: find.byType(CustomScrollView),
                    matching: find.byType(Scrollable))
                .first);
        await tester.pumpAndSettle();
        expect(find.text('到账数量'), findsOneWidget);
        expect(find.text('网络手续费'), findsOneWidget);
        final rect = tester.getRect(submit);
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(
            rect.bottom,
            lessThanOrEqualTo(
                layout.size.height - layout.keyboard.bottom - 20));
        await tester.tap(submit);
        expect(fixture.submits, 1);
        expect(tester.takeException(), isNull);
        final scaffold =
            tester.widget<Scaffold>(_key('internal-transfer-form'));
        final context = tester.element(_key('internal-transfer-form'));
        expect(scaffold.backgroundColor, FundPageColors.of(context).card);
      });
    }

    testWidgets('export internal withdrawal ${brightness.name}',
        skip: _previewDir.isEmpty, (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      for (final phone in [false, true]) {
        final boundary = GlobalKey();
        await _pump(
            tester,
            fixture.page(
                accountType: phone
                    ? FundTransferAccountType.phone
                    : FundTransferAccountType.email),
            brightness: brightness,
            boundaryKey: boundary);
        await tester.pumpAndSettle();
        final render = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(_previewDir).create(recursive: true);
          final name = phone ? 'internal-transfer-phone' : 'internal-transfer';
          await File('$_previewDir/$name-${brightness.name}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  testWidgets('type contact all help and history actions call their owner',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _pump(tester, fixture.page());
    await tester.tap(_key('internal-transfer-account-type'));
    await tester.tap(_key('internal-transfer-contacts'));
    await tester.tap(_key('internal-transfer-all'));
    await tester.tap(_key('internal-transfer-help'));
    await tester.tap(_key('internal-transfer-history'));
    expect(fixture.accountTaps, 1);
    expect(fixture.contactTaps, 1);
    expect(fixture.allTaps, 1);
    expect(fixture.amount.text, '12.123456');
    expect(fixture.helpTaps, 1);
    expect(fixture.historyTaps, 1);
    expect(
        tester.widget<FilledButton>(_key('internal-transfer-submit')).onPressed,
        isNull);
  });

  testWidgets('country code defaults to +86 only for phone input',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _pump(
        tester, fixture.page(accountType: FundTransferAccountType.phone));
    expect(find.text('+86'), findsOneWidget);
    expect(_key('internal-transfer-area-code'), findsOneWidget);
    for (final type in [
      FundTransferAccountType.uid,
      FundTransferAccountType.email,
      FundTransferAccountType.account,
    ]) {
      await _pump(tester, fixture.page(accountType: type));
      expect(_key('internal-transfer-area-code'), findsNothing);
      expect(find.text('+86'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  for (final state in [
    (locked: true, loading: false),
    (locked: false, loading: true),
  ]) {
    testWidgets(
        'country code cannot change when locked=${state.locked} loading=${state.loading}',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await _pump(
          tester,
          fixture.page(
              accountType: FundTransferAccountType.phone,
              locked: state.locked,
              loading: state.loading));
      final prefix = _key('internal-transfer-area-code');
      expect(find.text('+86'), findsOneWidget);
      expect(tester.widget<InkWell>(prefix).onTap, isNull);
      expect(fixture.areaCodeTaps, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending withdrawal locks inputs and permits confirming payment',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await _pump(
        tester, fixture.page(locked: true, pending: true, canSubmit: true));
    expect(
        tester
            .widget<TextFormField>(_key('internal-transfer-recipient'))
            .enabled,
        isFalse);
    expect(tester.widget<TextFormField>(_key('fund-amount')).enabled, isFalse);
    expect(tester.widget<TextButton>(_key('internal-transfer-all')).onPressed,
        isNull);
    expect(find.text('继续支付'), findsOneWidget);
    await tester.tap(_key('internal-transfer-submit'));
    expect(fixture.submits, 1);
  });

  testWidgets('form validates actual user input and shows coin-specific labels',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.recipientValidator =
        (value) => value?.contains('@') == true ? null : '请输入有效邮箱';
    fixture.amountValidator = (value) => value == '1.23' ? null : '请输入有效金额';
    await _pump(
        tester, fixture.page(currency: FundCurrency.bi99, available: '5.00'));
    expect(find.text('提现 99币'), findsOneWidget);
    expect(find.text('最少 0.01'), findsOneWidget);
    expect(find.text('可用：5.00 99币'), findsOneWidget);
    expect(fixture.formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('请输入有效邮箱'), findsOneWidget);
    await tester.enterText(
        _key('internal-transfer-recipient'), 'test@example.com');
    await tester.enterText(_key('fund-amount'), '1.23');
    expect(fixture.formKey.currentState!.validate(), isTrue);
    expect(fixture.recipientEdited, 1);
    expect(fixture.edited, 1);
    expect(tester.takeException(), isNull);
  });
}
