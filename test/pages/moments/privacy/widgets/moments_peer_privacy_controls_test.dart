import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:openim/pages/moments/privacy/widgets/moments_peer_privacy_controls.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';

import '../privacy_test_store.dart';

const _blocked = ValueKey('moments_peer_blocked_viewer_switch');
const _hidden = ValueKey('moments_peer_hidden_author_switch');
const _retry = ValueKey('moments_peer_privacy_retry');
const _saveAgain = ValueKey('moments_peer_privacy_persistence_retry');
const _peer = 'peer-im-id';

class _Api extends MomentsApi {
  final commands = <String>[];
  int settingsReads = 0;
  int capabilitiesReads = 0;
  bool supportsMoments = true;
  bool settingsEnabled = true;
  Object? nextError;
  Completer<MomentsSettings>? nextCommandGate;

  @override
  Future<MomentsCapabilities> capabilities() async {
    ++capabilitiesReads;
    return MomentsCapabilities(
        supportsMoments: supportsMoments,
        settingsEnabled: settingsEnabled,
        readEnabled: true,
        interactionsEnabled: true);
  }

  @override
  Future<MomentsSettings> settings() async {
    ++settingsReads;
    throw StateError('GET settings must not hydrate privacy choices');
  }

  Future<MomentsSettings> _command(String kind, String id, bool enabled) async {
    commands.add('$kind:$id:$enabled');
    final gate = nextCommandGate;
    nextCommandGate = null;
    final error = nextError;
    nextError = null;
    if (gate != null) await gate.future;
    if (error != null) throw error;
    return MomentsSettings.fromJson({});
  }

  @override
  Future<MomentsSettings> setBlockedViewer(String id, bool enabled) =>
      _command('blocked', id, enabled);

  @override
  Future<MomentsSettings> setHiddenAuthor(String id, bool enabled) =>
      _command('hidden', id, enabled);

  @override
  Future<MomentsPageResult<MomentPost>> feed(
          {String? cursor, int pageSize = 20}) async =>
      const MomentsPageResult(items: []);

  @override
  Future<MomentsPageResult<MomentNotification>> notifications(
          {String? cursor, int pageSize = 20}) async =>
      const MomentsPageResult(items: []);
}

class _GatedStore extends MemoryPrivacySelectionStore {
  Completer<MomentsPrivacySelections>? nextRead;

  @override
  Future<MomentsPrivacySelections> load(
      {required String ownerUserId, required String baseUrl}) async {
    final gate = nextRead;
    nextRead = null;
    if (gate != null) return gate.future;
    return super.load(ownerUserId: ownerUserId, baseUrl: baseUrl);
  }
}

MomentsRepository _repository(_Api api, MemoryPrivacySelectionStore store,
        {String Function()? account}) =>
    MomentsRepository(
      api: api,
      privacySelectionStore: store,
      userIdProvider: account ?? () => 'me',
      environmentProvider: () => 'test',
      friendLoader: () async => [const MomentUser(userId: _peer)],
      subscribeToSdk: false,
    );

Widget _host(MomentsRepository repository,
        {String peer = _peer,
        Widget? separator,
        Locale locale = const Locale('zh', 'CN'),
        bool dark = false,
        double textScale = 1}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
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
        home: Scaffold(
          body: SingleChildScrollView(
            child: Material(
              child: MomentsPeerPrivacyControls(
                  key: const ValueKey('peer-controls'),
                  userId: peer,
                  repository: repository,
                  separator: separator),
            ),
          ),
        ),
      ),
    );

CupertinoSwitch _switch(WidgetTester tester, Key key) =>
    tester.widget<CupertinoSwitch>(find.byKey(key));

void main() {
  late _Api api;
  late MemoryPrivacySelectionStore store;
  late MomentsRepository repository;
  setUp(() {
    api = _Api();
    store = MemoryPrivacySelectionStore();
    repository = _repository(api, store);
  });
  tearDown(() {
    repository.dispose();
    Styles.isDark = false;
  });

  testWidgets('hydration reserves switch space and never shows false choices',
      (tester) async {
    repository.dispose();
    final gated = _GatedStore();
    gated.nextRead = Completer<MomentsPrivacySelections>();
    final gate = gated.nextRead!;
    repository = _repository(api, gated);
    await tester.pumpWidget(_host(repository));
    await tester.pump();
    final initialSize =
        tester.getSize(find.byKey(const ValueKey('peer-controls')));
    expect(find.byType(CupertinoSwitch), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsNWidgets(2));
    gate.complete(MomentsPrivacySelections(blockedViewerIds: [_peer]));
    await tester.pumpAndSettle();
    expect(_switch(tester, _blocked).value, isTrue);
    expect(_switch(tester, _hidden).value, isFalse);
    expect(tester.getSize(find.byKey(const ValueKey('peer-controls'))),
        initialSize);
    expect(api.settingsReads, 0);
  });

  testWidgets(
      'two exact rows use confirmed device choices without GET settings',
      (tester) async {
    store.seed(
        ownerUserId: 'me',
        baseUrl: 'test',
        value: MomentsPrivacySelections(blockedViewerIds: [_peer]));
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();
    expect(find.text('不让他看我的朋友圈'), findsOneWidget);
    expect(find.text('不看他的朋友圈'), findsOneWidget);
    expect(find.byType(SettingsCell), findsNWidgets(2));
    for (final cell
        in tester.widgetList<SettingsCell>(find.byType(SettingsCell))) {
      expect(cell.showArrow, isFalse);
      expect(cell.showDivider, isFalse);
    }
    expect(_switch(tester, _blocked).value, isTrue);
    expect(_switch(tester, _hidden).value, isFalse);
    expect(_switch(tester, _hidden).onChanged, isNotNull);
    expect(tester.widget<Divider>(find.byType(Divider)).indent, 16);
    expect(tester.widgetList<Tooltip>(find.byType(Tooltip)).first.message,
        contains('此设备'));
    expect(api.settingsReads, 0);
    expect(api.commands, isEmpty);
  });

  testWidgets('both switches wait for acknowledgement without optimistic state',
      (tester) async {
    final gate = api.nextCommandGate = Completer<MomentsSettings>();
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_blocked));
    await tester.pump();
    expect(api.commands, ['blocked:$_peer:true']);
    expect(_switch(tester, _blocked).value, isFalse);
    expect(_switch(tester, _blocked).onChanged, isNull);
    expect(_switch(tester, _hidden).onChanged, isNull);
    expect(repository.privacySelections.blockedViewerIds, isEmpty);
    gate.complete(MomentsSettings.fromJson({}));
    await tester.pumpAndSettle();
    expect(_switch(tester, _blocked).value, isTrue);
    expect(_switch(tester, _hidden).onChanged, isNotNull);
    await tester.tap(find.byKey(_hidden));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_blocked));
    await tester.pumpAndSettle();
    expect(api.commands,
        ['blocked:$_peer:true', 'hidden:$_peer:true', 'blocked:$_peer:false']);
    expect(repository.privacySelections.hiddenAuthorIds, [_peer]);
    expect(api.settingsReads, 0);
  });

  testWidgets('unknown command result retries only the same target and intent',
      (tester) async {
    api.nextError = const MomentsException('结果未知', unknownResult: true);
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_hidden));
    await tester.pumpAndSettle();
    expect(repository.privacySelections.hiddenAuthorIds, isEmpty);
    expect(_switch(tester, _hidden).value, isFalse);
    expect(_switch(tester, _blocked).onChanged, isNull);
    await tester.tap(find.byKey(_retry));
    await tester.pumpAndSettle();
    expect(api.commands, ['hidden:$_peer:true', 'hidden:$_peer:true']);
    expect(_switch(tester, _hidden).value, isTrue);
    expect(find.byKey(_retry), findsNothing);
  });

  testWidgets(
      'device save failure retries persistence without resending command',
      (tester) async {
    store.failApply = true;
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_blocked));
    await tester.pumpAndSettle();
    expect(_switch(tester, _blocked).value, isTrue);
    expect(find.text('权限已保存，本机记录未能保存。'), findsOneWidget);
    expect(find.byKey(_retry), findsNothing);
    store.failApply = false;
    await tester.tap(find.byKey(_saveAgain));
    await tester.pumpAndSettle();
    expect(api.commands, ['blocked:$_peer:true']);
    expect(store.applies, 2);
    expect(find.byKey(_saveAgain), findsNothing);
  });

  for (final closeSettingsOnly in [false, true]) {
    testWidgets(
        'closed ${closeSettingsOnly ? 'settings' : 'moments'} disables writes and can retry',
        (tester) async {
      api.supportsMoments = closeSettingsOnly;
      api.settingsEnabled = false;
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();
      expect(_switch(tester, _blocked).onChanged, isNull);
      expect(_switch(tester, _hidden).onChanged, isNull);
      expect(api.commands, isEmpty);
      api.supportsMoments = true;
      api.settingsEnabled = true;
      await tester.tap(find.byKey(_retry));
      await tester.pumpAndSettle();
      expect(_switch(tester, _blocked).onChanged, isNotNull);
      expect(api.capabilitiesReads, 2);
      expect(api.settingsReads, 0);
    });
  }

  testWidgets(
      'failed local hydration disables editing and recovers independently',
      (tester) async {
    store.failLoad = true;
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();
    expect(_switch(tester, _blocked).onChanged, isNull);
    expect(api.commands, isEmpty);
    store.failLoad = false;
    await tester.tap(find.byKey(_retry));
    await tester.pumpAndSettle();
    expect(_switch(tester, _blocked).onChanged, isNotNull);
    expect(api.settingsReads, 0);
  });

  testWidgets(
      'switched account discards late command and cannot retry for new owner',
      (tester) async {
    var account = 'me';
    final scoped = _repository(api, store, account: () => account);
    addTearDown(scoped.dispose);
    final gate = api.nextCommandGate = Completer<MomentsSettings>();
    await tester.pumpWidget(_host(scoped));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_hidden));
    await tester.pump();
    account = 'other-account';
    await scoped.loadPrivacySelections();
    await tester.pump();
    gate.complete(MomentsSettings.fromJson({}));
    await tester.pumpAndSettle();
    expect(scoped.privacySelections.hiddenAuthorIds, isEmpty);
    expect(_switch(tester, _hidden).onChanged, isNull);
    expect(_switch(tester, _hidden).value, isFalse);
    expect(tester.widget<TextButton>(find.byKey(_retry)).onPressed, isNull);
    expect(api.commands, ['hidden:$_peer:true']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late hydration cannot expose a previous account selection',
      (tester) async {
    var account = 'me';
    final gatedStore = _GatedStore();
    final gate = gatedStore.nextRead = Completer<MomentsPrivacySelections>();
    final scoped = _repository(api, gatedStore, account: () => account);
    addTearDown(scoped.dispose);
    await tester.pumpWidget(_host(scoped));
    await tester.pump();
    expect(find.byType(CupertinoSwitch), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsNWidgets(2));
    account = 'other-account';
    await scoped.loadPrivacySelections();
    await tester.pump();
    gate.complete(MomentsPrivacySelections(blockedViewerIds: [_peer]));
    await tester.pumpAndSettle();
    expect(_switch(tester, _blocked).value, isFalse);
    expect(scoped.privacySelections.blockedViewerIds, isEmpty);
    expect(api.commands, isEmpty);
  });

  testWidgets(
      'changed peer keeps late success and retries away from new contact',
      (tester) async {
    final gate = api.nextCommandGate = Completer<MomentsSettings>();
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_blocked));
    await tester.pump();
    await tester.pumpWidget(_host(repository, peer: 'next-peer'));
    await tester.pumpAndSettle();
    gate.complete(MomentsSettings.fromJson({}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(_switch(tester, _blocked).value, isFalse);
    expect(_switch(tester, _hidden).onChanged, isNotNull);
    expect(api.commands, ['blocked:$_peer:true']);
    expect(repository.privacySelections.blockedViewerIds, [_peer]);
    expect(find.byKey(_retry), findsNothing);
  });

  testWidgets('repository replacement ignores an old failed command retry',
      (tester) async {
    final gate = api.nextCommandGate = Completer<MomentsSettings>();
    api.nextError = const MomentsException('请求失败');
    final replacementApi = _Api();
    final replacement =
        _repository(replacementApi, MemoryPrivacySelectionStore());
    addTearDown(replacement.dispose);
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_hidden));
    await tester.pump();
    await tester.pumpWidget(_host(replacement));
    await tester.pumpAndSettle();
    gate.complete(MomentsSettings.fromJson({}));
    await tester.pumpAndSettle();
    expect(_switch(tester, _hidden).value, isFalse);
    expect(_switch(tester, _hidden).onChanged, isNotNull);
    expect(find.byKey(_retry), findsNothing);
    expect(replacementApi.commands, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared repository notifications refresh the confirmed snapshot',
      (tester) async {
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();
    await repository.setHiddenAuthor(_peer, true);
    await tester.pumpAndSettle();
    expect(_switch(tester, _hidden).value, isTrue);
    expect(api.settingsReads, 0);
  });

  testWidgets(
      'disposing pending controls never restarts or applies widget state',
      (tester) async {
    final gate = api.nextCommandGate = Completer<MomentsSettings>();
    await tester.pumpWidget(_host(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_hidden));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete(MomentsSettings.fromJson({}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(api.commands, ['hidden:$_peer:true']);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'English rows fit narrow ${dark ? 'dark' : 'light'} view with large text and injected separator',
        (tester) async {
      tester.view.physicalSize = const Size(320, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Styles.isDark = dark;
      await tester.pumpWidget(_host(repository,
          dark: dark,
          textScale: 2,
          locale: const Locale('en', 'US'),
          separator:
              const SizedBox(key: ValueKey('profile-separator'), height: 1)));
      await tester.pumpAndSettle();
      expect(find.text('Hide my moments from them'), findsOneWidget);
      expect(find.text('Hide their moments'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-separator')), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
