import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/internal_transfer/data/fund_transfer_recipient_source.dart';
import 'package:openim/pages/fund/internal_transfer/presentation/fund_internal_transfer_actions.dart';
import 'package:openim/pages/fund/internal_transfer/presentation/fund_internal_transfer_form.dart';
import 'package:openim/services/fund_models.dart';
import 'package:openim_common/openim_common.dart';

const _previewDir =
    String.fromEnvironment('FUND_TRANSFER_ACCOUNT_SHEET_PREVIEW_DIR');

const _languages = [
  (
    locale: Locale('zh', 'CN'),
    title: '选择账号类型',
    labels: ['99号', '邮箱', '手机号'],
    current: '当前选择',
    cancel: '取消',
  ),
  (
    locale: Locale('zh', 'TW'),
    title: '選擇帳號類型',
    labels: ['99號', '電子郵件', '手機號碼'],
    current: '目前選擇',
    cancel: '取消',
  ),
  (
    locale: Locale('en', 'US'),
    title: 'Choose account type',
    labels: ['99Chat ID', 'Email', 'Phone number'],
    current: 'Current selection',
    cancel: 'Cancel',
  ),
  (
    locale: Locale('ja', 'JP'),
    title: 'アカウントの種類を選択',
    labels: ['99Chat ID', 'メールアドレス', '電話番号'],
    current: '現在の選択',
    cancel: 'キャンセル',
  ),
  (
    locale: Locale('ko', 'KR'),
    title: '계정 유형 선택',
    labels: ['99Chat ID', '이메일', '전화번호'],
    current: '현재 선택',
    cancel: '취소',
  ),
];

Finder _type(FundTransferAccountType type) =>
    find.byKey(ValueKey('internal-transfer-type-${type.name}'));

class _Fixture {
  final results = <FundTransferAccountType?>[];
  final recipient = TextEditingController();
  final amount = TextEditingController();
  final amountFocus = FocusNode();
  final formKey = GlobalKey<FormState>();

  void dispose() {
    recipient.dispose();
    amount.dispose();
    amountFocus.dispose();
  }

  Future<void> open(
    WidgetTester tester, {
    Locale locale = const Locale('zh', 'CN'),
    Brightness brightness = Brightness.light,
    Size size = const Size(375, 812),
    double scale = 1,
    FundTransferAccountType selected = FundTransferAccountType.account,
    GlobalKey? boundaryKey,
    bool previewForm = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      dispose();
    });
    Styles.isDark = brightness == Brightness.dark;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        locale: locale,
        supportedLocales:
            _languages.map((language) => language.locale).toList(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          brightness: brightness,
          fontFamily: _previewDir.isEmpty ? null : 'FundSheetPreviewCjk',
          colorScheme: ColorScheme.fromSeed(
              seedColor: AppTokens.accent, brightness: brightness),
        ),
        builder: (context, child) => RepaintBoundary(
          key: boundaryKey,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(top: 24, bottom: 20),
            ),
            child: child!,
          ),
        ),
        home: Builder(builder: (context) {
          Future<void> openSheet() async {
            results.add(await showFundTransferAccountTypes(context, selected));
          }

          if (!previewForm) {
            return Scaffold(
                body: TextButton(
                    onPressed: openSheet, child: const Text('Open')));
          }
          return FundInternalTransferForm(
            currency: FundCurrency.usdt,
            accountType: selected,
            recipientInput: recipient,
            amount: amount,
            amountFocus: amountFocus,
            formKey: formKey,
            isLocked: false,
            isLoading: false,
            isSubmitting: false,
            canSubmit: false,
            hasPending: false,
            passwordSet: true,
            available: '12.345678',
            arrivalAmount: '0.00',
            onEdited: () {},
            onRecipientEdited: () {},
            onChooseAccountType: openSheet,
            onChooseRecipient: () {},
            onAll: () {},
            onSubmit: () {},
            onReload: () {},
            onSetPassword: () {},
            onClose: () {},
            onHelp: () {},
            onHistory: () {},
            validateAmount: (_) => null,
            validateRecipient: (_) => null,
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(previewForm
        ? find.byKey(const ValueKey('internal-transfer-account-type'))
        : find.text('Open'));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(() async {
    if (_previewDir.isEmpty) return;
    for (final font in [
      (name: 'FundSheetPreviewCjk', path: 'C:/Windows/Fonts/msyh.ttc'),
      (name: 'CupertinoSystemText', path: 'C:/Windows/Fonts/msyh.ttc'),
      (name: 'CupertinoSystemDisplay', path: 'C:/Windows/Fonts/msyh.ttc'),
      (
        name: 'MaterialIcons',
        path:
            'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      final bytes = await File(font.path).readAsBytes();
      await (FontLoader(font.name)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final language in _languages) {
      for (final layout in const [
        (size: Size(375, 812), scale: 1.0),
        (size: Size(320, 640), scale: 2.0),
        (size: Size(812, 375), scale: 2.0),
      ]) {
        testWidgets(
            '${language.locale} ${brightness.name} choices fit ${layout.size} at ${layout.scale}x',
            (tester) async {
          final fixture = _Fixture();
          await fixture.open(tester,
              locale: language.locale,
              brightness: brightness,
              size: layout.size,
              scale: layout.scale,
              selected: FundTransferAccountType.phone);
          final sheet = find.byType(CupertinoActionSheet);
          expect(sheet, findsOneWidget);
          expect(find.text(language.title), findsOneWidget);
          expect(find.text(language.current), findsOneWidget);
          expect(find.text(language.cancel), findsOneWidget);
          expect(_type(FundTransferAccountType.uid), findsNothing);
          expect(tester.takeException(), isNull);
          for (final (index, type) in const [
            FundTransferAccountType.account,
            FundTransferAccountType.email,
            FundTransferAccountType.phone,
          ].indexed) {
            final choice = _type(type);
            expect(
                find.descendant(
                    of: choice, matching: find.text(language.labels[index])),
                findsOneWidget);
            expect(tester.widget<Semantics>(choice).properties.selected,
                type == FundTransferAccountType.phone);
            expect(tester.getSize(choice).height, greaterThanOrEqualTo(44));
          }
          final phone = _type(FundTransferAccountType.phone);
          await tester.ensureVisible(phone);
          await tester.pumpAndSettle();
          await tester.tap(phone);
          await tester.pumpAndSettle();
          expect(fixture.results, [FundTransferAccountType.phone]);
          expect(sheet, findsNothing);
          expect(find.text('Open'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('${brightness.name} cancel returns no account type',
        (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester, brightness: brightness);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(fixture.results, [null]);
      expect(find.byType(CupertinoActionSheet), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${brightness.name} actual account sheet preview',
        skip: _previewDir.isEmpty, (tester) async {
      final boundary = GlobalKey();
      final fixture = _Fixture();
      await fixture.open(tester,
          brightness: brightness, previewForm: true, boundaryKey: boundary);
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(_previewDir).create(recursive: true);
        await File('$_previewDir/transfer-account-sheet-${brightness.name}.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    });
  }

  for (final closeWithBack in [false, true]) {
    testWidgets(
        '${closeWithBack ? 'back' : 'barrier'} dismisses only the sheet',
        (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      if (closeWithBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(20, 20));
      }
      await tester.pumpAndSettle();
      expect(fixture.results, [null]);
      expect(find.byType(CupertinoActionSheet), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
