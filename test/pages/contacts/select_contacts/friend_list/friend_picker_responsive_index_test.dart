import 'dart:io';

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_view.dart';
import 'package:openim_common/openim_common.dart';

import 'support/friend_picker_presence_fixture.dart';

Finder _letter(String value) =>
    find.descendant(of: find.byType(IndexBar), matching: find.text(value));

List<ISUserInfo> _alphabetFriends() => [
      for (final tag in [...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''), '#'])
        ISUserInfo.fromJson({
          'userID': 'friend-$tag',
          'nickname': tag == '#' ? '123 Friend' : '$tag Friend',
          'tagIndex': tag,
          'namePinyin': '$tag FRIEND',
        }),
    ];

void _expectIndexFits(WidgetTester tester) {
  final listRect = tester.getRect(find.byType(AzListView));
  final index = tester.widget<IndexBar>(find.byType(IndexBar));
  expect(index.data, [...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''), '#']);
  expect(index.itemHeight * index.data.length,
      lessThanOrEqualTo(listRect.height + .01));
  for (final tag in index.data) {
    final label = _letter(tag);
    expect(label.hitTestable(), findsOneWidget);
    final rect = tester.getRect(label);
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(rect.top, greaterThanOrEqualTo(listRect.top - .01));
    expect(rect.bottom, lessThanOrEqualTo(listRect.bottom + .01));
    expect(paragraph.size.height,
        greaterThanOrEqualTo(paragraph.getMaxIntrinsicHeight(rect.width) - .01),
        reason: 'The $tag label must fit, not only its index item container.');
    expect(paragraph.didExceedMaxLines, isFalse);
  }
  expect(tester.takeException(), isNull);
}

class _Selection extends SelectContactsLogic {
  _Selection() {
    action = SelAction.addMember;
    openSelectedSheet = false;
    checkedList['friend'] =
        UserInfo(userID: 'friend', nickname: 'Selected friend');
  }

  int confirmations = 0;
  int expandedSelections = 0;

  @override
  // Only route initialization and navigation are replaced; labels stay real.
  // ignore: must_call_super
  void onInit() {}

  @override
  void onReady() {}

  @override
  Future<void> confirmSelectedList() async => confirmations++;

  @override
  void viewSelectedContactsList() => expandedSelections++;
}

Future<void> _loadMetricsFont() async {
  // Use the fonts shipped with the running Flutter SDK, not machine fonts.
  // Ahem gives bold/regular identical advances and would hide this regression.
  var directory = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++, directory = directory.parent) {
    final fontDirectory = Directory('${directory.path}/material_fonts');
    if (!fontDirectory.existsSync()) continue;
    final loader = FontLoader('PickerMetricsRoboto');
    for (final face in ['regular', 'bold']) {
      loader.addFont(File('${fontDirectory.path}/roboto-$face.ttf')
          .readAsBytes()
          .then(ByteData.sublistView));
    }
    await loader.load();
    return;
  }
  throw StateError('The running Flutter SDK material fonts were not found.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadMetricsFont);
  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} 27 letters fit 320px at 200% and reach the last friend',
        (tester) async {
      final fixture = FriendPickerPresenceFixture(
          action: SelAction.forward, data: _alphabetFriends());
      await fixture.open(tester,
          brightness: brightness, width: 320, textScale: 2);
      _expectIndexFits(tester);
      await tester.tap(_letter('#'));
      await tester.pumpAndSettle();
      expect(friendPickerRow('friend-#').hitTestable(), findsOneWidget);
      await tester.tap(friendPickerRow('friend-#'));
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList.keys, ['friend-#']);
      _expectIndexFits(tester);

      // Selection makes the bottom bar taller; all letters must still fit.
      await tester.tap(_letter('A'));
      await tester.pumpAndSettle();
      expect(friendPickerRow('friend-A').hitTestable(), findsOneWidget);
      final drag = await tester.startGesture(tester.getCenter(_letter('A')));
      await drag.moveTo(tester.getCenter(_letter('M')));
      await tester.pumpAndSettle();
      await drag.moveTo(tester.getCenter(_letter('#')));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(friendPickerRow('friend-#').hitTestable(), findsOneWidget);
      expect(fixture.contacts.owners.values.single, contains('friend-#'));
      _expectIndexFits(tester);
    });
  }

  testWidgets('English system bold confirmation fits its actual rendered text',
      (tester) async {
    Get.testMode = true;
    final selection = Get.put<SelectContactsLogic>(_Selection()) as _Selection;
    final oldDark = Styles.isDark;
    Styles.isDark = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 844);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
      Styles.isDark = oldDark;
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        theme: ThemeData(fontFamily: 'PickerMetricsRoboto'),
        translations: TranslationService(),
        locale: const Locale('en', 'US'),
        supportedLocales: const [Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              boldText: true, textScaler: const TextScaler.linear(1.25)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
              alignment: Alignment.bottomCenter, child: CheckedConfirmView()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final label = find.text('Confirm (1/999)');
    final selected = find.text('Selected (1)');
    expect(label, findsOneWidget);
    expect(selected, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(label);
    final effective = (paragraph.text as TextSpan).style!;
    expect(effective.fontWeight, FontWeight.bold);
    final regular = TextPainter(
      text: TextSpan(
          text: 'Confirm (1/999)',
          style: effective.copyWith(fontWeight: FontWeight.normal)),
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
      locale: const Locale('en', 'US'),
    )..layout();
    final requiredWidth = paragraph.getMaxIntrinsicWidth(double.infinity);
    expect(requiredWidth, greaterThan(regular.width + 1),
        reason: 'This font must expose the system-bold width difference.');
    regular.dispose();
    expect(paragraph.size.width, greaterThanOrEqualTo(requiredWidth - .01));
    expect(paragraph.didExceedMaxLines, isFalse);
    final buttonRect = tester.getRect(find.byType(Button));
    expect(tester.getCenter(selected).dy,
        inInclusiveRange(buttonRect.top, buttonRect.bottom),
        reason: 'Exercise the measured horizontal layout.');
    await tester.tap(selected);
    await tester.pump();
    expect(selection.expandedSelections, 1);
    await tester.tap(label);
    await tester.pump();
    expect(selection.confirmations, 1);
    expect(tester.takeException(), isNull);
  });
}
