import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/moments_notifications_page.dart';
import 'package:openim/pages/moments/moments_privacy_friend_picker.dart';
import 'package:openim/pages/moments/moments_privacy_list_page.dart';
import 'package:openim/pages/moments/moments_settings_page.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';

import 'pages/moments/privacy/privacy_test_store.dart';

const _friend = MomentUser(userId: 'friend', nickname: 'Friend');
const _other = MomentUser(userId: 'other', nickname: 'Other');

class _Api extends MomentsApi {
  Completer<void>? readGate;
  bool enabled = true;
  bool failNotifications = false;
  bool failSettingsSave = false;
  bool failRemove = false;
  MomentsSettings remoteSettings = const MomentsSettings(
    visibleRangeDays: 90,
    blockedViewerIds: ['friend'],
    hiddenAuthorIds: ['other'],
    version: 7,
  );
  final List<String?> notificationCursors = [];
  final List<List<String>> readIds = [];
  final List<int?> readSequences = [];
  final List<String?> watermarks = [];
  final List<String> removedBlocked = [];
  final List<String> addedBlocked = [];
  int? rangeWritten;
  int? expectedVersionWritten;
  int readResult = 0;
  final Map<String, MomentsPageResult<MomentNotification>> pages = {
    '': const MomentsPageResult(
      items: [
        MomentNotification(
            notificationId: 'n1',
            actor: _friend,
            type: 'LIKE',
            momentId: 'm1',
            seq: 100)
      ],
      unreadCount: 1,
      readThroughSeq: 100,
      seenWatermark: 'watermark-100',
    ),
  };

  @override
  Future<MomentsCapabilities> capabilities() async => MomentsCapabilities(
        enabled: enabled,
        readEnabled: enabled,
        publishEnabled: enabled,
        interactionsEnabled: enabled,
        settingsEnabled: enabled,
      );

  @override
  Future<MomentsPageResult<MomentNotification>> notifications(
      {String? cursor, int pageSize = 20}) async {
    notificationCursors.add(cursor);
    if (failNotifications) throw const MomentsException('网络连接失败');
    return pages[cursor ?? '']!;
  }

  @override
  Future<int> markNotificationsRead(
      {List<String> notificationIds = const [],
      int? readThroughSeq,
      String? seenWatermark}) async {
    readIds.add(notificationIds);
    readSequences.add(readThroughSeq);
    watermarks.add(seenWatermark);
    if (readGate != null) await readGate!.future;
    return readResult;
  }

  @override
  Future<MomentsSettings> settings() async => remoteSettings;

  @override
  Future<MomentsSettings> updateSettings(
      {int? visibleRangeDays,
      String? coverMediaId,
      bool clearCover = false,
      required int expectedVersion}) async {
    rangeWritten = visibleRangeDays;
    expectedVersionWritten = expectedVersion;
    if (failSettingsSave) throw const MomentsException('设置保存失败');
    remoteSettings = MomentsSettings(
      visibleRangeDays: visibleRangeDays ?? remoteSettings.visibleRangeDays,
      blockedViewerIds: remoteSettings.blockedViewerIds,
      hiddenAuthorIds: remoteSettings.hiddenAuthorIds,
      blockedViewersLoaded: remoteSettings.blockedViewersLoaded,
      hiddenAuthorsLoaded: remoteSettings.hiddenAuthorsLoaded,
      version: expectedVersion + 1,
    );
    return remoteSettings;
  }

  @override
  Future<MomentsSettings> setBlockedViewer(String id, bool blocked) async {
    if (failRemove) throw const MomentsException('设置保存失败');
    if (!blocked) removedBlocked.add(id);
    if (blocked) addedBlocked.add(id);
    remoteSettings = MomentsSettings(
      visibleRangeDays: remoteSettings.visibleRangeDays,
      blockedViewerIds: blocked
          ? [...remoteSettings.blockedViewerIds, id]
          : remoteSettings.blockedViewerIds
              .where((entry) => entry != id)
              .toList(),
      hiddenAuthorIds: remoteSettings.hiddenAuthorIds,
      blockedViewersLoaded: remoteSettings.blockedViewersLoaded,
      hiddenAuthorsLoaded: remoteSettings.hiddenAuthorsLoaded,
      version: remoteSettings.version + 1,
    );
    return remoteSettings;
  }
}

MomentsRepository _repository(_Api api) => MomentsRepository(
      api: api,
      userIdProvider: () => 'me',
      environmentProvider: () => 'test',
      friendLoader: () async => [_friend, _other],
      privacySelectionStore: MemoryPrivacySelectionStore(
          initial: MomentsPrivacySelections(
              blockedViewerIds: ['friend'], hiddenAuthorIds: ['other'])),
      subscribeToSdk: false,
    );

Widget _host(Widget child, {bool dark = false, double textScale = 1}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) {
        Styles.isDark = dark;
        return MaterialApp(
          locale: const Locale('en', 'US'),
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

void main() {
  testWidgets(
      'repeated notification taps open once and submit one read command',
      (tester) async {
    final api = _Api()..readGate = Completer<void>();
    final repository = _repository(api);
    addTearDown(repository.dispose);
    final opened = <String>[];
    await tester.pumpWidget(_host(MomentsNotificationsPage(
        repository: repository, onOpenMoment: opened.add)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friend'));
    await tester.tap(find.text('Friend'));
    await tester.pump();
    expect(opened, ['m1']);
    expect(api.readIds, [
      ['n1']
    ]);
    api.readGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'friend search can clear a query and selecting dismisses the keyboard',
      (tester) async {
    final repository = _repository(_Api());
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsPrivacyFriendPicker(
        repository: repository, title: 'Select friends')));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('moments_privacy_friend_search'));
    await tester.enterText(search, 'Friend');
    await tester.pumpAndSettle();
    expect(find.text('Other'), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('moments_privacy_search_clear')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.text('Other'), findsOneWidget);
    await tester.enterText(search, 'Other');
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester
        .tap(find.byKey(const ValueKey('moments_privacy_friend_other')));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('moments_privacy_picker_done')))
            .onPressed,
        isNotNull);
  });
  testWidgets('entering notifications does not mark unseen messages read',
      (tester) async {
    final api = _Api();
    final repository = _repository(api);
    addTearDown(repository.dispose);
    String? opened;
    await tester.pumpWidget(_host(MomentsNotificationsPage(
        repository: repository, onOpenMoment: (id) => opened = id)));
    await tester.pumpAndSettle();
    expect(api.readIds, isEmpty);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == '1 unread interactions'),
        findsOneWidget);
    await tester.tap(find.text('Friend'));
    await tester.pumpAndSettle();
    expect(opened, 'm1');
    expect(api.readIds.single, ['n1']);
    expect(api.readSequences.single, isNull);
  });

  testWidgets(
      'wire notifications without body text retain like comment and reply labels',
      (tester) async {
    final api = _Api();
    api.pages[''] = MomentsPageResult(items: [
      for (final type in ['like', 'comment', 'reply'])
        MomentNotification.fromJson({
          'notificationID': 'notification-$type',
          'momentID': 'moment-$type',
          'commentID': type == 'like' ? '' : 'comment-$type',
          'type': type,
          'seq': 100,
          'unread': true,
          'unavailable': false,
          'actor': _friend.toJson(),
        })
    ], unreadCount: 3, seenWatermark: 'watermark-100', readThroughSeq: 100);
    final repository = _repository(api);
    addTearDown(repository.dispose);
    final opened = <String>[];
    await tester.pumpWidget(_host(MomentsNotificationsPage(
        repository: repository, onOpenMoment: opened.add)));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == 'Liked your moment'),
        findsOneWidget);
    expect(find.textContaining('Commented on your moment'), findsOneWidget);
    expect(find.textContaining('Replied to a comment'), findsOneWidget);
    expect(find.textContaining('1970'), findsNothing);
    await tester.tap(find.textContaining('Replied to a comment'));
    await tester.pumpAndSettle();
    expect(opened, ['moment-reply']);
    expect(api.readIds.single, ['notification-reply']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'explicit read-all submits the server watermark and preserves newer unread',
      (tester) async {
    final api = _Api()..readResult = 1;
    final repository = _repository(api);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsNotificationsPage(
        repository: repository, onOpenMoment: (_) {})));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('moments_notifications_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read all'));
    await tester.pumpAndSettle();
    expect(api.readSequences.single, 100);
    expect(api.watermarks.single, 'watermark-100');
    expect(api.readIds.single, isEmpty);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == '1 unread interactions'),
        findsOneWidget);
  });

  testWidgets(
      'notification pagination uses the cursor and distinguishes errors from empty',
      (tester) async {
    final api = _Api()..failNotifications = true;
    api.pages[''] = const MomentsPageResult(
      items: [
        MomentNotification(
            notificationId: 'n1', actor: _friend, type: 'LIKE', momentId: 'm1')
      ],
      nextCursor: 'next',
      hasMore: true,
    );
    api.pages['next'] = const MomentsPageResult(items: [
      MomentNotification(
          notificationId: 'n2', actor: _other, type: 'COMMENT', momentId: 'm2'),
    ]);
    final repository = _repository(api);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsNotificationsPage(
        repository: repository, onOpenMoment: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('Could not load interactions'), findsOneWidget);
    expect(find.text('No interactions yet'), findsNothing);
    api.failNotifications = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(api.notificationCursors.last, 'next');
    expect(find.text('Friend'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
  });

  testWidgets(
      'unexpected nonfriend notification is hidden together with untrusted unread badge',
      (tester) async {
    final api = _Api();
    api.pages[''] = const MomentsPageResult(items: [
      MomentNotification(
          notificationId: 'n1', actor: _friend, type: 'LIKE', momentId: 'm1'),
      MomentNotification(
          notificationId: 'secret',
          actor: MomentUser(userId: 'stranger', nickname: 'Secret actor'),
          type: 'COMMENT',
          momentId: 'secret-post',
          momentText: 'Private text'),
      MomentNotification(
          notificationId: 'own-hidden-reply',
          actor: MomentUser(userId: 'me', nickname: 'My hidden reply'),
          type: 'COMMENT_REPLY',
          momentId: 'm1',
          replyToUser:
              MomentUser(userId: 'stranger', nickname: 'Hidden target')),
    ], unreadCount: 3);
    final repository = _repository(api);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsNotificationsPage(
        repository: repository, onOpenMoment: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('Friend'), findsOneWidget);
    expect(find.text('Secret actor'), findsNothing);
    expect(find.text('My hidden reply'), findsNothing);
    expect(find.text('Hidden target'), findsNothing);
    expect(find.textContaining('Private text'), findsNothing);
    expect(find.text('3 unread interactions'), findsNothing);
    expect(repository.unreadCount, 0);
  });

  testWidgets('disabled capability is shown separately from an empty inbox',
      (tester) async {
    final api = _Api()..enabled = false;
    final repository = _repository(api);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsNotificationsPage(
        repository: repository, onOpenMoment: (_) {})));
    await tester.pumpAndSettle();
    expect(find.text('Moments is not available yet'), findsOneWidget);
    expect(find.text('No interactions yet'), findsNothing);
    expect(api.notificationCursors, isEmpty);
  });

  testWidgets(
      'range restores from the API and failed versioned save retains original selection',
      (tester) async {
    final api = _Api()..failSettingsSave = true;
    final repository = _repository(api);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsSettingsPage(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Last 3 months'), findsOneWidget);
    await tester.tap(find.text('Visible range for friends'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 3 days'));
    await tester.pumpAndSettle();
    expect(api.rangeWritten, 3);
    expect(api.expectedVersionWritten, 7);
    expect(find.text('Last 3 months'), findsOneWidget);
    expect(find.text('Last 3 days'), findsNothing);
    expect(find.text('Could not update settings'), findsOneWidget);
  });

  testWidgets(
      'single privacy deletion failure keeps the item and retry uses one relationship API',
      (tester) async {
    final api = _Api()..failRemove = true;
    final repository = _repository(api);
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsPrivacyListPage(
        repository: repository, kind: MomentsPrivacyKind.blockedViewer)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Friend'), findsOneWidget);
    expect(find.text('Could not complete this action'), findsOneWidget);
    api.failRemove = false;
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Friend'), findsNothing);
    expect(api.removedBlocked, ['friend']);
    expect(repository.privacySelections.hiddenAuthorIds, ['other']);
  });

  testWidgets(
      'a same-account server change invalidates an open range selection',
      (tester) async {
    final api = _Api();
    var environment = 'first-server';
    final repository = MomentsRepository(
      api: api,
      userIdProvider: () => 'me',
      environmentProvider: () => environment,
      friendLoader: () async => [_friend, _other],
      privacySelectionStore: MemoryPrivacySelectionStore(),
      subscribeToSdk: false,
    );
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsSettingsPage(repository: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visible range for friends'));
    await tester.pumpAndSettle();
    environment = 'second-server';
    await repository.loadSettings();
    await tester.pump();
    await tester.tap(find.text('Last 3 days'));
    await tester.pumpAndSettle();
    expect(api.rangeWritten, isNull);
    expect(find.text('Last 3 months'), findsNothing);
  });

  testWidgets(
      'privacy picker clears previous-account search and friends immediately',
      (tester) async {
    var owner = 'me';
    final repository = MomentsRepository(
      api: _Api(),
      userIdProvider: () => owner,
      environmentProvider: () => 'test',
      privacySelectionStore: MemoryPrivacySelectionStore(),
      friendLoader: () async => [_friend, _other],
      subscribeToSdk: false,
    );
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsPrivacyFriendPicker(
        repository: repository, title: 'Select friends')));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('moments_privacy_friend_search'));
    await tester.enterText(search, 'Friend');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, 'Friend');
    expect(find.byKey(const ValueKey('moments_privacy_friend_friend')),
        findsOneWidget);
    owner = 'next-account';
    await repository.loadFriends(force: true);
    await tester.pump();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.text('Friend'), findsNothing);
    expect(find.byKey(const ValueKey('moments_privacy_friend_friend')),
        findsNothing);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('moments_privacy_picker_done')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'privacy picker friendship failure is retryable and never shown as empty',
      (tester) async {
    var failFriends = true;
    final repository = MomentsRepository(
      api: _Api(),
      userIdProvider: () => 'me',
      environmentProvider: () => 'test',
      privacySelectionStore: MemoryPrivacySelectionStore(),
      friendLoader: () async {
        if (failFriends) throw const MomentsException('好友读取失败');
        return [_friend, _other];
      },
      subscribeToSdk: false,
    );
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(
        MomentsPrivacyFriendPicker(
          repository: repository,
          title: 'Add friends',
          excludedUserIds: const ['friend'],
        ),
        dark: true));
    await tester.pumpAndSettle();
    expect(find.text('Could not load friends'), findsOneWidget);
    expect(find.text('No friends yet'), findsNothing);
    final disabledDone = tester.widget<TextButton>(
      find.byKey(const ValueKey('moments_privacy_picker_done')),
    );
    expect(disabledDone.onPressed, isNull);
    failFriends = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load friends'), findsNothing);
    expect(find.text('Friend'), findsNothing);
    expect(find.text('Other'), findsOneWidget);
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.label == '1 friends selected'),
        findsOneWidget);
  });

  testWidgets(
      'privacy add selects fresh repository friends and saves one relationship',
      (tester) async {
    final api = _Api();
    var friendLoads = 0;
    final repository = MomentsRepository(
      api: api,
      userIdProvider: () => 'me',
      environmentProvider: () => 'test',
      privacySelectionStore: MemoryPrivacySelectionStore(
          initial: MomentsPrivacySelections(
              blockedViewerIds: ['friend'], hiddenAuthorIds: ['other'])),
      friendLoader: () async {
        ++friendLoads;
        return [_friend, _other];
      },
      subscribeToSdk: false,
    );
    addTearDown(repository.dispose);
    await tester.pumpWidget(_host(MomentsPrivacyListPage(
      repository: repository,
      kind: MomentsPrivacyKind.blockedViewer,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add friends'));
    await tester.pumpAndSettle();
    expect(friendLoads, 2);
    expect(find.text('Friend'), findsOneWidget);
    await tester.tap(find.text('Other'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('moments_privacy_picker_done')));
    await tester.pumpAndSettle();
    expect(api.addedBlocked, ['other']);
    expect(repository.privacySelections.blockedViewerIds, ['friend', 'other']);
    expect(repository.privacySelections.hiddenAuthorIds, ['other']);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'notifications and privacy stay usable with large English text in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());
      final api = _Api();
      final repository = _repository(api);
      addTearDown(repository.dispose);
      await tester.pumpWidget(_host(
          MomentsNotificationsPage(
              repository: repository, onOpenMoment: (_) {}),
          dark: dark,
          textScale: 1.8));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(_host(MomentsSettingsPage(repository: repository),
          dark: dark, textScale: 1.8));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
