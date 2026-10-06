import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/moments_privacy_list_page.dart';
import 'package:openim/pages/moments/moments_settings_page.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';

import 'privacy_test_store.dart';

const _friend = MomentUser(userId: 'friend', nickname: 'Friend');
const _other = MomentUser(userId: 'other', nickname: 'Other');

class _Api extends MomentsApi {
  final commands = <String>[];
  int settingsReads = 0;
  String? failUserId;
  int failuresRemaining = 0;
  Completer<void>? waitForCommand;

  @override
  Future<MomentsCapabilities> capabilities() async => const MomentsCapabilities(
      enabled: true,
      readEnabled: true,
      interactionsEnabled: true,
      settingsEnabled: true);

  @override
  Future<MomentsSettings> settings() async {
    ++settingsReads;
    return MomentsSettings.fromJson({
      'visibleRangeDays': 90,
      'coverMediaID': '',
      'coverPath': '',
      'version': 7,
      'viewerContextVersion': 'context-7',
    });
  }

  Future<MomentsSettings> _command(String kind, String id, bool enabled) async {
    commands.add('$kind:${enabled ? 'add' : 'remove'}:$id');
    final wait = waitForCommand;
    waitForCommand = null;
    if (wait != null) await wait.future;
    if (id == failUserId && failuresRemaining > 0) {
      --failuresRemaining;
      throw const MomentsException('设置保存失败');
    }
    // Real mutation acknowledgements and GET settings do not expose lists.
    return MomentsSettings.fromJson({});
  }

  @override
  Future<MomentsSettings> setBlockedViewer(String id, bool blocked) =>
      _command('block', id, blocked);

  @override
  Future<MomentsSettings> setHiddenAuthor(String id, bool hidden) =>
      _command('hide', id, hidden);

  @override
  Future<MomentsPageResult<MomentPost>> feed(
          {String? cursor, int pageSize = 20}) async =>
      const MomentsPageResult(items: []);

  @override
  Future<MomentsPageResult<MomentNotification>> notifications(
          {String? cursor, int pageSize = 20}) async =>
      const MomentsPageResult(items: []);
}

MomentsRepository _repository(_Api api, MemoryPrivacySelectionStore store,
        {String Function()? userIdProvider,
        String Function()? environmentProvider}) =>
    MomentsRepository(
      api: api,
      privacySelectionStore: store,
      userIdProvider: userIdProvider ?? () => 'me',
      environmentProvider: environmentProvider ?? () => 'test',
      friendLoader: () async => [_friend, _other],
      subscribeToSdk: false,
    );

Widget _host(Widget child,
        {bool dark = false,
        double textScale = 1,
        Locale locale = const Locale('en', 'US')}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) {
        Styles.isDark = dark;
        return MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: child,
        );
      },
    );

Future<void> _choose(
    WidgetTester tester, String action, List<String> friends) async {
  await tester.ensureVisible(find.text(action));
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
  for (final friend in friends) {
    await tester.tap(find.text(friend));
  }
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('moments_privacy_picker_done')));
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in MomentsPrivacyKind.values) {
    final command = kind == MomentsPrivacyKind.blockedViewer ? 'block' : 'hide';
    testWidgets('${kind.name} can add friends without GET settings lists',
        (tester) async {
      final api = _Api();
      final store = MemoryPrivacySelectionStore();
      final repository = _repository(api, store);
      addTearDown(repository.dispose);
      await tester.pumpWidget(
          _host(MomentsPrivacyListPage(repository: repository, kind: kind)));
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate((widget) =>
              widget is Semantics &&
              widget.properties.label == 'None selected'),
          findsOneWidget);
      expect(find.text('Could not load this privacy list'), findsNothing);
      expect(api.settingsReads, 0);
      expect(
          tester
              .widget<InkWell>(
                  find.byKey(const ValueKey('moments_privacy_add')))
              .onTap,
          isNotNull);
      await _choose(tester, 'Add friends', ['Friend']);
      expect(api.commands, ['$command:add:friend']);
      expect(find.text('Friend'), findsOneWidget);
      expect(
          find.byWidgetPredicate((widget) =>
              widget is Semantics &&
              widget.properties.label == 'None selected'),
          findsNothing);
      final ids = kind == MomentsPrivacyKind.blockedViewer
          ? repository.privacySelections.blockedViewerIds
          : repository.privacySelections.hiddenAuthorIds;
      expect(ids, ['friend']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${kind.name} can cancel a friend absent from this device list',
        (tester) async {
      final api = _Api();
      final repository = _repository(api, MemoryPrivacySelectionStore());
      addTearDown(repository.dispose);
      await tester.pumpWidget(
          _host(MomentsPrivacyListPage(repository: repository, kind: kind)));
      await tester.pumpAndSettle();
      await _choose(tester, 'Choose friends to remove', ['Other']);
      expect(api.commands, ['$command:remove:other']);
      expect(repository.privacySelections.blockedViewerIds, isEmpty);
      expect(repository.privacySelections.hiddenAuthorIds, isEmpty);
      expect(
          find.byWidgetPredicate((widget) =>
              widget is Semantics &&
              widget.properties.label == 'None selected'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an existing friend remains selectable for an idempotent PUT',
      (tester) async {
    final api = _Api();
    final store = MemoryPrivacySelectionStore(
        initial: MomentsPrivacySelections(blockedViewerIds: ['friend']));
    final repository = _repository(api, store);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsPrivacyListPage(
        repository: repository, kind: MomentsPrivacyKind.blockedViewer)));
    await tester.pumpAndSettle();
    await _choose(tester, 'Add friends', ['Friend']);
    expect(api.commands, ['block:add:friend']);
    expect(repository.privacySelections.blockedViewerIds, ['friend']);
    await repository.loadSettings();
    await tester.pumpAndSettle();
    expect(find.text('Friend'), findsOneWidget);
    expect(repository.privacySelections.blockedViewerIds, ['friend']);
  });

  testWidgets('partial failure retries only remaining choices', (tester) async {
    final api = _Api()
      ..failUserId = 'other'
      ..failuresRemaining = 1;
    final repository = _repository(api, MemoryPrivacySelectionStore());
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsPrivacyListPage(
        repository: repository, kind: MomentsPrivacyKind.blockedViewer)));
    await tester.pumpAndSettle();
    await _choose(tester, 'Add friends', ['Friend', 'Other']);
    expect(api.commands, ['block:add:friend', 'block:add:other']);
    expect(repository.privacySelections.blockedViewerIds, ['friend']);
    expect(find.text('Friend'), findsOneWidget);
    expect(find.text('Retry remaining choices'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry remaining choices'));
    await tester.tap(find.text('Retry remaining choices'));
    await tester.pumpAndSettle();
    expect(api.commands,
        ['block:add:friend', 'block:add:other', 'block:add:other']);
    expect(repository.privacySelections.blockedViewerIds, ['friend', 'other']);
    expect(find.text('Could not complete this action'), findsNothing);
    expect(find.text('Other'), findsOneWidget);
  });

  testWidgets('a failed local save never replays the successful PUT',
      (tester) async {
    final api = _Api();
    final store = MemoryPrivacySelectionStore()..failApply = true;
    final repository = _repository(api, store);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsPrivacyListPage(
        repository: repository, kind: MomentsPrivacyKind.blockedViewer)));
    await tester.pumpAndSettle();
    await _choose(tester, 'Add friends', ['Friend']);
    expect(api.commands, ['block:add:friend']);
    expect(repository.privacySelections.blockedViewerIds, ['friend']);
    expect(find.text('Could not save these choices on this device'),
        findsOneWidget);
    store.failApply = false;
    await tester.ensureVisible(find.text('Save again'));
    await tester.tap(find.text('Save again'));
    await tester.pumpAndSettle();
    expect(api.commands, ['block:add:friend']);
    expect(repository.privacyPersistenceError, isNull);
    expect(
        find.text('Could not save these choices on this device'), findsNothing);
    expect(find.text('Friend'), findsOneWidget);
  });

  testWidgets('a real local read failure remains retryable', (tester) async {
    final api = _Api();
    final store = MemoryPrivacySelectionStore()..failLoad = true;
    final repository = _repository(api, store);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsPrivacyListPage(
        repository: repository, kind: MomentsPrivacyKind.blockedViewer)));
    await tester.pumpAndSettle();
    expect(find.text('Could not complete this action'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.label == 'None selected'),
        findsNothing);
    expect(
        find.text('Could not save these choices on this device'), findsNothing);
    expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('moments_privacy_add')))
            .onTap,
        isNull);
    store.failLoad = false;
    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.label == 'None selected'),
        findsOneWidget);
    expect(api.settingsReads, 0);
  });

  for (final changeServer in [false, true]) {
    testWidgets(
        '${changeServer ? 'server' : 'account'} change stops the pending batch and clears old choices',
        (tester) async {
      var user = 'me';
      var server = 'test';
      final api = _Api();
      final release = Completer<void>();
      final repository = _repository(api, MemoryPrivacySelectionStore(),
          userIdProvider: () => user, environmentProvider: () => server);
      addTearDown(repository.dispose);
      await tester.pumpWidget(_host(MomentsPrivacyListPage(
          repository: repository, kind: MomentsPrivacyKind.blockedViewer)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add friends'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Friend'));
      await tester.tap(find.text('Other'));
      await tester.pump();
      api.waitForCommand = release;
      await tester
          .tap(find.byKey(const ValueKey('moments_privacy_picker_done')));
      await tester.pump();
      expect(api.commands, ['block:add:friend']);
      if (changeServer) {
        server = 'another-server';
      } else {
        user = 'another-user';
      }
      await repository.loadPrivacySelections();
      release.complete();
      await tester.pumpAndSettle();
      expect(api.commands, ['block:add:friend']);
      expect(repository.privacySelections.blockedViewerIds, isEmpty);
      expect(find.text('Friend'), findsNothing);
      expect(find.text('Other'), findsNothing);
      expect(find.text('Retry remaining choices'), findsNothing);
      expect(
          tester
              .widget<InkWell>(
                  find.byKey(const ValueKey('moments_privacy_add')))
              .onTap,
          isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'settings counts reflect device choices despite omitted GET lists',
      (tester) async {
    final api = _Api();
    final repository = _repository(
        api,
        MemoryPrivacySelectionStore(
            initial: MomentsPrivacySelections(blockedViewerIds: ['friend'])));
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsSettingsPage(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('1 friend'), findsOneWidget);
    expect(find.text('None selected'), findsOneWidget);
    expect(find.text('Not loaded'), findsNothing);
    expect(find.text('Last 3 months'), findsOneWidget);
    await repository.loadSettings();
    await tester.pumpAndSettle();
    expect(find.text('1 friend'), findsOneWidget);
    expect(find.text('None selected'), findsOneWidget);
    expect(repository.privacySelections.blockedViewerIds, ['friend']);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'empty device choices work with large text in ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _repository(_Api(), MemoryPrivacySelectionStore());
      addTearDown(repository.dispose);
      await tester.pumpWidget(_host(
          MomentsPrivacyListPage(
              repository: repository, kind: MomentsPrivacyKind.blockedViewer),
          dark: dark,
          textScale: 1.8,
          locale: const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate((widget) =>
              widget is Semantics && widget.properties.label == '未选取'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester
          .ensureVisible(find.byKey(const ValueKey('moments_privacy_add')));
      await tester.tap(find.byKey(const ValueKey('moments_privacy_add')));
      await tester.pumpAndSettle();
      expect(find.text('Friend'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
