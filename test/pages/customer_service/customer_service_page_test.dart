import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/customer_service/customer_service_sheet.dart';
import 'package:openim/pages/customer_service/content/customer_service_content.dart';
import 'package:openim/pages/customer_service/customer_service_tokens.dart';
import 'package:openim/pages/customer_service/data/data.dart';
import 'package:openim/pages/customer_service/models/customer_service_chat_entry.dart';
import 'package:openim/pages/customer_service/widgets/customer_service_faq_panel.dart';
import 'package:openim/pages/customer_service/widgets/customer_service_message_view.dart';
import 'package:openim_common/openim_common.dart';

import 'customer_service_test_fakes.dart';

Future<void> _loadFonts() async {
  final file = File('C:/Windows/Fonts/msyh.ttc');
  if (!await file.exists()) return;
  final bytes = ByteData.sublistView(await file.readAsBytes());
  for (final family in [
    'SupportPreviewFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Finder _chatScrollable() => find
    .descendant(
        of: find.byKey(const ValueKey('customer-service-messages')),
        matching: find.byType(Scrollable))
    .first;

ScrollPosition _chatPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(_chatScrollable()).position;

List<CustomerServiceMessage> _variedHistory(int count) => List.generate(
    count,
    (index) => customerServiceTestMessage(
        '$index',
        index == count - 1
            ? 'Newest restored reply'
            : 'Earlier reply $index\n${List.filled(index % 5 + 1, 'Support response with details to wrap across lines.').join('\n')}',
        createdAt: DateTime.utc(2026, 1, 1, 12, index)));

void _resumeLifecycle(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Future<void> _open(WidgetTester tester, CustomerServiceTestHarness harness,
    {Brightness brightness = Brightness.light,
    Locale locale = const Locale('zh', 'CN'),
    TextScaler textScaler = TextScaler.noScaling,
    bool disableAnimations = false,
    Size screenSize = const Size(375, 812),
    GlobalKey? screenshotKey}) async {
  await tester.runAsync(_loadFonts);
  _resumeLifecycle(tester);
  tester.view.physicalSize = screenSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(() async {
    _resumeLifecycle(tester);
    final sheet = find.byKey(const ValueKey('customer-service-sheet'));
    if (sheet.evaluate().isNotEmpty) {
      Navigator.of(tester.element(sheet), rootNavigator: true).pop();
      await _flush(tester);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await _flush(tester);
    harness.dispose();
  });
  await tester.pumpWidget(GetMaterialApp(
    locale: locale,
    supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    translations: TranslationService(),
    theme: ThemeData(brightness: brightness, fontFamily: 'SupportPreviewFont'),
    builder: (context, child) {
      ScreenUtil.init(context, designSize: const Size(375, 812));
      return RepaintBoundary(
          key: screenshotKey,
          child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: textScaler, disableAnimations: disableAnimations),
              child: child!));
    },
    home: Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                  onPressed: () => showCustomerServiceSheet(context,
                      controller: harness.controller),
                  child: const Text('Open support'),
                ))),
  ));
  await tester.tap(find.text('Open support'));
  await _flush(tester);
}

Future<void> _close(
    WidgetTester tester, CustomerServiceTestHarness harness) async {
  await tester.tap(find.byKey(const ValueKey('customer-service-close')));
  await _flush(tester);
  expect(find.byKey(const ValueKey('customer-service-sheet')), findsNothing);
  expect(harness.api.disposed, isTrue);
  expect(harness.store.disposed, isTrue);
  expect(harness.cable.disposed, isTrue);
  await tester.pumpWidget(const SizedBox.shrink());
  await _flush(tester);
  expect(tester.takeException(), isNull);
}

Future<void> _screenshot(
    WidgetTester tester, GlobalKey key, String name) async {
  // Let loaded-font glyphs finish rasterizing before capturing the preview.
  for (var frame = 0; frame < 2; frame++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory =
        Platform.environment['CUSTOMER_SERVICE_SCREENSHOT_DIR'] ?? '.dart_tool';
    await Directory(directory).create(recursive: true);
    await File('$directory/customer-service-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets('all FAQ questions are fully visible on opening in $brightness',
        (tester) async {
      final harness = CustomerServiceTestHarness();
      final key = GlobalKey();
      await _open(tester, harness, brightness: brightness, screenshotKey: key);
      final list = find.byKey(const ValueKey('customer-service-faq-faq'));
      final viewport = tester.getRect(list);
      for (final question in customerServiceCategories.first.questions) {
        final row =
            find.byKey(ValueKey('customer-service-question-${question.id}'));
        expect(row, findsOneWidget);
        final rect = tester.getRect(row);
        expect(rect.top, greaterThanOrEqualTo(viewport.top));
        expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(row.hitTestable(), findsOneWidget);
      }
      await _screenshot(tester, key, '${brightness.name}-faq-complete');
      await tester.tap(
          find.byKey(const ValueKey('customer-service-question-faq_network')));
      await _flush(tester);
      expect(harness.controller.questionId, 'faq_network');
      expect(find.byKey(const ValueKey('customer-service-answer-faq_network')),
          findsOneWidget);
      await _close(tester, harness);
    });

    testWidgets(
        'FAQ questions and answer remain reachable with large text and keyboard in $brightness',
        (tester) async {
      final harness = CustomerServiceTestHarness();
      final key = GlobalKey();
      await _open(tester, harness,
          brightness: brightness,
          screenSize: const Size(320, 812),
          textScaler: TextScaler.linear(1.8),
          screenshotKey: key);
      final input = find.byKey(const ValueKey('customer-service-input'));
      await tester.enterText(input, 'Keep this draft while reading help');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await _flush(tester);
      final list = find.byKey(const ValueKey('customer-service-faq-faq'));
      final scrollable = _chatScrollable();
      expect(find.descendant(of: list, matching: find.byType(Scrollable)),
          findsNothing);
      final lastQuestion =
          find.byKey(const ValueKey('customer-service-question-faq_network'));
      await tester.scrollUntilVisible(lastQuestion, 80, scrollable: scrollable);
      await tester.ensureVisible(lastQuestion);
      await _flush(tester);
      final viewport = tester
          .getRect(find.byKey(const ValueKey('customer-service-messages')));
      final lastRect = tester.getRect(lastQuestion);
      expect(lastRect.top, greaterThanOrEqualTo(viewport.top - 1));
      expect(lastRect.bottom, lessThanOrEqualTo(viewport.bottom + 1));
      expect(lastQuestion.hitTestable(), findsOneWidget);
      await _screenshot(tester, key, '${brightness.name}-faq-small-keyboard');
      await tester.tap(lastQuestion);
      await _flush(tester);

      final answer =
          find.byKey(const ValueKey('customer-service-answer-faq_network'));
      expect(find.descendant(of: answer, matching: find.byType(Scrollable)),
          findsNothing);
      final position = _chatPosition(tester);
      expect(position.maxScrollExtent, greaterThan(0));
      for (var swipe = 0;
          swipe < 12 && position.pixels < position.maxScrollExtent;
          swipe++) {
        await tester.dragFrom(viewport.center, const Offset(0, -160));
        await _flush(tester);
      }
      expect(position.pixels, closeTo(position.maxScrollExtent, 1));
      final question = customerServiceCategories.first.questions.last;
      final text = find.text(question.answer(tester.element(answer)));
      expect(
          tester.getRect(text).bottom, lessThanOrEqualTo(viewport.bottom + 1));
      await _screenshot(
          tester, key, '${brightness.name}-answer-small-keyboard');
      final back = find.byKey(const ValueKey('customer-service-answer-back'));
      await tester.scrollUntilVisible(back, -80, scrollable: scrollable);
      await tester.ensureVisible(back);
      await _flush(tester);
      await tester.tap(back);
      await _flush(tester);
      expect(harness.controller.questionId, isNull);
      expect(list, findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text,
          'Keep this draft while reading help');
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await _flush(tester);
      await _close(tester, harness);
    });

    testWidgets(
        '80 percent support sheet keeps its top stable with the keyboard in $brightness',
        (tester) async {
      final harness = CustomerServiceTestHarness();
      final key = GlobalKey();
      await _open(tester, harness, brightness: brightness, screenshotKey: key);
      final sheet = find.byKey(const ValueKey('customer-service-sheet'));
      final before = tester.getRect(sheet);
      expect(before.height, closeTo(812 * 0.8, 1));
      expect(before.bottom, closeTo(812, 1));
      expect(find.byType(CustomerServiceFaqPanel), findsOneWidget);
      expect(tester.widget<Material>(sheet).color,
          CustomerServiceTokens.surface(tester.element(sheet)));
      await _screenshot(tester, key, '${brightness.name}-faq');
      final closeBefore =
          tester.getRect(find.byKey(const ValueKey('customer-service-close')));
      await tester.tap(find.byKey(const ValueKey('customer-service-input')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await _flush(tester);
      expect(tester.getRect(sheet).top, closeTo(before.top, 1));
      expect(
          tester
              .getRect(find.byKey(const ValueKey('customer-service-close')))
              .top,
          closeTo(closeBefore.top, 1));
      expect(
          tester
              .getRect(find.byKey(const ValueKey('customer-service-input')))
              .bottom,
          lessThanOrEqualTo(812 - 300));
      tester.view.resetViewInsets();
      await _flush(tester);
      await _close(tester, harness);
    });

    testWidgets('FAQ category, answer and back navigation work in $brightness',
        (tester) async {
      final harness = CustomerServiceTestHarness();
      await _open(tester, harness, brightness: brightness);
      await tester.tap(
          find.byKey(const ValueKey('customer-service-question-faq_official')));
      await _flush(tester);
      expect(find.byKey(const ValueKey('customer-service-answer-faq_official')),
          findsOneWidget);
      expect(find.text('https://official.invalid'), findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('customer-service-answer-back')));
      await _flush(tester);
      expect(find.byKey(const ValueKey('customer-service-faq-faq')),
          findsOneWidget);
      final category =
          find.byKey(const ValueKey('customer-service-category-auth'));
      await tester.tap(category);
      await _flush(tester);
      expect(harness.controller.selectedCategoryId, 'auth');
      expect(harness.controller.questionId, isNull);
      expect(find.byKey(const ValueKey('customer-service-faq-auth')),
          findsOneWidget);
      await _close(tester, harness);
    });

    testWidgets(
        'loading history does not block composer sends or late replies in $brightness',
        (tester) async {
      final harness = CustomerServiceTestHarness();
      final history = Completer<List<CustomerServiceMessage>>();
      harness.api.onList = () => history.future;
      final key = GlobalKey();
      await _open(tester, harness, brightness: brightness, screenshotKey: key);
      expect(harness.controller.loading, isTrue);
      final input = find.byKey(const ValueKey('customer-service-input'));
      await tester.enterText(input, 'A live question');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('customer-service-send')));
      await _flush(tester);
      expect(harness.api.sends.single.content, 'A live question');
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      history.complete([
        customerServiceTestMessage('10', 'Earlier answer',
            createdAt: DateTime.utc(2025, 12, 31))
      ]);
      await _flush(tester);
      expect(find.byType(CustomerServiceMessageView), findsNWidgets(2));
      expect(find.text('A live question'), findsOneWidget);
      expect(find.text('Earlier answer'), findsOneWidget);
      await _screenshot(tester, key, '${brightness.name}-chat');
      await _close(tester, harness);
    });
  }

  for (final locale in [const Locale('zh', 'CN'), const Locale('en', 'US')]) {
    testWidgets('both category rows fit with large text in $locale',
        (tester) async {
      final harness = CustomerServiceTestHarness();
      await _open(tester, harness,
          locale: locale,
          screenSize: const Size(320, 812),
          textScaler: TextScaler.linear(1.8));
      final header =
          tester.getRect(find.byKey(const ValueKey('customer-service-header')));
      for (final category in customerServiceCategories) {
        final chip =
            find.byKey(ValueKey('customer-service-category-${category.id}'));
        final rect = tester.getRect(chip);
        expect(rect.top, greaterThanOrEqualTo(header.top));
        expect(rect.bottom, lessThanOrEqualTo(header.bottom));
        expect(chip.hitTestable(), findsOneWidget);
      }
      await tester
          .tap(find.byKey(const ValueKey('customer-service-category-other')));
      await _flush(tester);
      expect(harness.controller.selectedCategoryId, 'other');
      expect(tester.takeException(), isNull);
      await _close(tester, harness);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'varied-height restored history reaches its real tail in $brightness',
        (tester) async {
      final harness = CustomerServiceTestHarness();
      harness.api.history = _variedHistory(60);
      await _open(tester, harness, brightness: brightness);
      await tester.pumpAndSettle();
      expect(_chatPosition(tester).extentAfter, closeTo(0, 1));
      expect(find.text('Newest restored reply').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester, harness);
    });

    testWidgets(
        'late restored history follows latest with large text and keyboard in $brightness',
        (tester) async {
      final harness = CustomerServiceTestHarness();
      final history = Completer<List<CustomerServiceMessage>>();
      harness.api.onList = () => history.future;
      await _open(tester, harness,
          brightness: brightness,
          screenSize: const Size(320, 812),
          textScaler: TextScaler.linear(1.8));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await _flush(tester);
      expect(_chatPosition(tester).extentAfter, greaterThan(80));
      history.complete(_variedHistory(40));
      await _flush(tester);
      await tester.pumpAndSettle();
      expect(_chatPosition(tester).extentAfter, closeTo(0, 1));
      expect(find.text('Newest restored reply').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await _flush(tester);
      await _close(tester, harness);
    });

    testWidgets(
        'categories stay fixed while FAQ and chat share the canvas in $brightness',
        (tester) async {
      final harness = CustomerServiceTestHarness();
      harness.api.history = List.generate(
          20,
          (index) => customerServiceTestMessage(
              '$index', 'Earlier reply $index',
              createdAt: DateTime.utc(2026, 1, 1, 12, index)));
      final key = GlobalKey();
      await _open(tester, harness, brightness: brightness, screenshotKey: key);
      await tester.pumpAndSettle();
      final position = _chatPosition(tester);
      expect(position.extentAfter, closeTo(0, 1));
      expect(find.text('Earlier reply 19').hitTestable(), findsOneWidget);

      position.jumpTo(0);
      await _flush(tester);
      final messages = find.byKey(const ValueKey('customer-service-messages'));
      final header = find.byKey(const ValueKey('customer-service-header'),
          skipOffstage: false);
      final question =
          find.byKey(const ValueKey('customer-service-question-faq_notify'));
      final headerBefore = tester.getRect(header);
      final chipRects = {
        for (final category in customerServiceCategories)
          category.id: tester.getRect(
              find.byKey(ValueKey('customer-service-category-${category.id}')))
      };
      final questionBefore = tester.getRect(question).top;
      expect(tester.widget(messages), isA<CustomScrollView>());
      expect(find.ancestor(of: header, matching: find.byType(CustomScrollView)),
          findsNothing);
      await tester.drag(question, const Offset(0, -110));
      await _flush(tester);
      expect(position.pixels, greaterThan(50));
      expect(tester.getRect(header), headerBefore);
      for (final category in customerServiceCategories) {
        final chip =
            find.byKey(ValueKey('customer-service-category-${category.id}'));
        expect(tester.getRect(chip), chipRects[category.id]);
        expect(chip.hitTestable(), findsOneWidget);
      }
      expect(tester.getRect(question).top, lessThan(questionBefore - 50));
      expect(find.byType(CustomerServiceFaqPanel), findsOneWidget);

      final input = find.byKey(const ValueKey('customer-service-input'));
      await tester.enterText(input, 'Keep this unfinished question');
      position.jumpTo(0);
      await _flush(tester);
      await tester.tap(question);
      await _flush(tester);
      final answer = find.byKey(
          const ValueKey('customer-service-answer-faq_notify'),
          skipOffstage: false);
      expect(answer, findsOneWidget);
      expect(find.descendant(of: answer, matching: find.byType(Scrollable)),
          findsNothing);
      await _screenshot(tester, key, '${brightness.name}-answer-inline');

      position.jumpTo(position.maxScrollExtent);
      await _flush(tester);
      expect(find.text('Earlier reply 19').hitTestable(), findsOneWidget);
      expect(tester.getRect(header), headerBefore);
      expect(tester.getRect(header).bottom,
          lessThanOrEqualTo(tester.getRect(messages).top));
      expect(answer, findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text,
          'Keep this unfinished question');
      expect(harness.api.listCalls, 1);
      expect(harness.api.sends, isEmpty);
      expect(tester.takeException(), isNull);
      await _screenshot(tester, key, '${brightness.name}-chat-scroll');
      for (final category in customerServiceCategories) {
        position.jumpTo(position.maxScrollExtent);
        await _flush(tester);
        final chip =
            find.byKey(ValueKey('customer-service-category-${category.id}'));
        expect(chip.hitTestable(), findsOneWidget);
        await tester.tap(chip);
        await _flush(tester);
        await tester.pumpAndSettle();
        expect(position.pixels, closeTo(0, 1));
        expect(harness.controller.selectedCategoryId, category.id);
        expect(find.byKey(ValueKey('customer-service-faq-${category.id}')),
            findsOneWidget);
        expect(tester.getRect(header), headerBefore);
        expect(tester.widget<TextField>(input).controller!.text,
            'Keep this unfinished question');
        expect(harness.api.listCalls, 1);
        expect(harness.api.sends, isEmpty);
      }
      expect(tester.takeException(), isNull);
      await _close(tester, harness);
    });

    testWidgets(
        'incoming replies preserve history position and sending returns to latest in $brightness',
        (tester) async {
      final harness = CustomerServiceTestHarness();
      harness.api.history = List.generate(
          24,
          (index) => customerServiceTestMessage(
              '$index', 'History reply $index',
              createdAt: DateTime.utc(2026, 1, 1, 12, index)));
      harness.api.onSend = (request) async => customerServiceTestMessage(
          '1001', request.content,
          echoId: request.echoId,
          type: 0,
          createdAt: DateTime.utc(2026, 1, 2, 12, 1));
      await _open(tester, harness, brightness: brightness);
      await tester.pumpAndSettle();
      final position = _chatPosition(tester);
      expect(position.extentAfter, closeTo(0, 1));
      final messages = find.byKey(const ValueKey('customer-service-messages'));
      await tester.drag(messages, const Offset(0, 220));
      await _flush(tester);
      final readingOffset = position.pixels;
      expect(position.extentAfter, greaterThan(80));
      final visibleIndices = [
        for (var index = 0; index < 24; index++)
          if (find
              .text('History reply $index')
              .hitTestable()
              .evaluate()
              .isNotEmpty)
            index
      ];
      expect(visibleIndices, isNotEmpty);
      final visibleHistory = find
          .text('History reply ${visibleIndices[visibleIndices.length ~/ 2]}');
      final before = tester.getRect(visibleHistory).top;
      harness.cable.message(customerServiceTestMessage('1000', 'New live reply',
          createdAt: DateTime.utc(2026, 1, 2, 12)));
      await _flush(tester);
      expect(position.pixels, closeTo(readingOffset, 1));
      expect(tester.getRect(visibleHistory).top, closeTo(before, 1));

      await tester.enterText(
          find.byKey(const ValueKey('customer-service-input')),
          'Reply while reading history');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('customer-service-send')));
      await _flush(tester);
      await tester.pumpAndSettle();
      expect(position.extentAfter, closeTo(0, 1));
      expect(find.text('Reply while reading history').hitTestable(),
          findsOneWidget);
      expect(find.byType(CustomerServiceFaqPanel, skipOffstage: false),
          findsOneWidget);
      expect(harness.api.sends.single.content, 'Reply while reading history');
      expect(tester.takeException(), isNull);
      await _close(tester, harness);
    });

    testWidgets('landscape help stays scrollable above keyboard in $brightness',
        (tester) async {
      final harness = CustomerServiceTestHarness();
      await _open(tester, harness,
          brightness: brightness,
          screenSize: const Size(640, 360),
          textScaler: TextScaler.linear(1.8));
      final input = find.byKey(const ValueKey('customer-service-input'));
      await tester.enterText(input, 'Landscape draft');
      tester.view.viewInsets = const FakeViewPadding(bottom: 100);
      await _flush(tester);
      final question =
          find.byKey(const ValueKey('customer-service-question-faq_network'));
      await tester.scrollUntilVisible(question, 80,
          scrollable: _chatScrollable());
      await tester.ensureVisible(question);
      await _flush(tester);
      expect(question.hitTestable(), findsOneWidget);
      await tester.tap(question);
      await _flush(tester);
      final position = _chatPosition(tester);
      expect(position.maxScrollExtent, greaterThan(0));
      position.jumpTo(position.maxScrollExtent);
      await _flush(tester);
      final answer =
          find.byKey(const ValueKey('customer-service-answer-faq_network'));
      final text = find.text(customerServiceCategories.first.questions.last
          .answer(tester.element(answer)));
      final viewport = tester
          .getRect(find.byKey(const ValueKey('customer-service-messages')));
      expect(
          tester.getRect(text).bottom, lessThanOrEqualTo(viewport.bottom + 1));
      expect(tester.getRect(input).bottom, lessThanOrEqualTo(260));
      expect(
          tester.widget<TextField>(input).controller!.text, 'Landscape draft');
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await _flush(tester);
      await _close(tester, harness);
    });
  }

  testWidgets('reduced-motion restored history reaches the actual latest reply',
      (tester) async {
    final harness = CustomerServiceTestHarness();
    harness.api.history = _variedHistory(60);
    await _open(tester, harness, disableAnimations: true);
    await tester.pumpAndSettle();
    expect(_chatPosition(tester).extentAfter, closeTo(0, 1));
    expect(find.text('Newest restored reply').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester, harness);
  });

  testWidgets(
      'late history does not move a reader who opened and scrolled help',
      (tester) async {
    final harness = CustomerServiceTestHarness();
    final history = Completer<List<CustomerServiceMessage>>();
    harness.api.onList = () => history.future;
    await _open(tester, harness,
        screenSize: const Size(320, 812), textScaler: TextScaler.linear(1.8));
    final question =
        find.byKey(const ValueKey('customer-service-question-faq_notify'));
    await tester.ensureVisible(question);
    await _flush(tester);
    await tester.tap(question);
    await _flush(tester);
    final messages = find.byKey(const ValueKey('customer-service-messages'));
    await tester.drag(messages, const Offset(0, -100));
    await _flush(tester);
    final position = _chatPosition(tester);
    final readingOffset = position.pixels;
    expect(readingOffset, greaterThan(0));
    history.complete(_variedHistory(40));
    await _flush(tester);
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(readingOffset, 1));
    expect(harness.controller.questionId, 'faq_notify');
    expect(position.extentAfter, greaterThan(80));
    expect(tester.takeException(), isNull);
    await _close(tester, harness);
  });

  testWidgets(
      'backgrounding clears typing and resumes the existing support session',
      (tester) async {
    final harness = CustomerServiceTestHarness();
    await _open(tester, harness);
    harness.cable.typing(true);
    await _flush(tester);
    expect(harness.controller.agentTyping, isTrue);
    expect(find.text('客服正在输入…'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _flush(tester);
    expect(harness.controller.agentTyping, isFalse);
    expect(harness.cable.suspensions, greaterThanOrEqualTo(1));
    _resumeLifecycle(tester);
    await _flush(tester);
    expect(find.text('客服正在输入…'), findsNothing);
    expect(harness.cable.connections, hasLength(2));
    expect(harness.cable.connections.last.conversationId,
        customerServiceTestSession.conversationId);
    await _close(tester, harness);
  });

  testWidgets('a failed message can be retried from its visible action',
      (tester) async {
    final harness = CustomerServiceTestHarness();
    harness.api.onSend = (_) async => throw StateError('offline');
    await _open(tester, harness);
    await tester.enterText(find.byKey(const ValueKey('customer-service-input')),
        'Retry this question');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('customer-service-send')));
    await _flush(tester);
    expect(find.text('发送失败，点击重试'), findsOneWidget);
    final echo = harness.controller.entries.single.echoId;
    harness.api.onSend = null;
    await tester.tap(find.byKey(ValueKey('customer-service-retry-$echo')));
    await _flush(tester);
    expect(harness.api.sends, hasLength(2));
    expect(
        harness.controller.entries.single.state, CustomerServiceSendState.sent);
    expect(find.text('发送失败，点击重试'), findsNothing);
    expect(find.text('Retry this question'), findsOneWidget);
    await _close(tester, harness);
  });

  testWidgets('closing during history loading ignores the late response',
      (tester) async {
    final harness = CustomerServiceTestHarness();
    final history = Completer<List<CustomerServiceMessage>>();
    harness.api.onList = () => history.future;
    await _open(tester, harness);
    expect(harness.controller.loading, isTrue);
    await _close(tester, harness);
    history.complete([customerServiceTestMessage('1', 'After closing')]);
    await _flush(tester);
    expect(harness.controller.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'attachment choices use the shared sheet and cancellation resumes chat',
      (tester) async {
    final harness = CustomerServiceTestHarness();
    await _open(tester, harness);
    await tester.tap(find.byKey(const ValueKey('customer-service-attach')));
    await _flush(tester);
    expect(find.text('添加附件'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await _flush(tester);
    await tester.pumpAndSettle();
    expect(find.text('添加附件'), findsNothing);
    expect(harness.api.sends, isEmpty);
    expect(harness.cable.connections, hasLength(2));
    await _close(tester, harness);
  });
}
