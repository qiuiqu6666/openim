import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_repository.dart';
import 'privacy_test_store.dart';

class RemotePrivacyApi extends MomentsApi {
  final blocked = <String>{};
  final hidden = <String>{};
  int version = 0;
  bool failRead = false;
  Completer<MomentsSettings>? readGate;
  Completer<MomentsSettings>? writeGate;
  bool writeStarted = false;
  MomentsSettings snapshot() => MomentsSettings.fromJson({
        'blockedViewerIDs': blocked.toList(),
        'hiddenAuthorIDs': hidden.toList(),
        'privacyListsLoaded': true,
        'updatedAt': version == 0 ? 0 : 1700000000000 + version,
        'version': version,
      });
  @override
  Future<MomentsCapabilities> capabilities() async =>
      MomentsCapabilities.fromJson({'supportsMoments': true});
  @override
  Future<MomentsSettings> settings() async {
    if (failRead) throw const MomentsException('offline');
    if (readGate != null) return readGate!.future;
    return snapshot();
  }

  @override
  Future<MomentsSettings> setBlockedViewer(String id, bool enabled) async {
    writeStarted = true;
    if (writeGate != null) return writeGate!.future;
    enabled ? blocked.add(id) : blocked.remove(id);
    version++;
    return snapshot();
  }
}

MomentsRepository repository(
        RemotePrivacyApi api, MemoryPrivacySelectionStore store,
        {String Function()? owner}) =>
    MomentsRepository(
        api: api,
        userIdProvider: owner ?? () => 'me',
        environmentProvider: () => 'test',
        privacySelectionStore: store,
        friendLoader: () async => [],
        subscribeToSdk: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'two devices restore server choices and authoritative empty removes stale cache',
      () async {
    final api = RemotePrivacyApi();
    final a = repository(api, MemoryPrivacySelectionStore());
    final b = repository(api, MemoryPrivacySelectionStore());
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setBlockedViewer('peer', true);
    await b.loadPrivacySelections();
    expect(b.privacySelections.blockedViewerIds, ['peer']);
    expect(b.settings!.updatedAt, 1700000000001);
    await b.setBlockedViewer('peer', false);
    await a.loadPrivacySelections(force: true);
    expect(a.privacySelections.blockedViewerIds, isEmpty);
    expect(a.settings!.version, 2);
  });
  test('delayed GET cannot overwrite a newer confirmed modification', () async {
    final api = RemotePrivacyApi();
    final r = repository(api, MemoryPrivacySelectionStore());
    addTearDown(r.dispose);
    await r.loadPrivacySelections();
    final old = api.snapshot();
    final gate = api.readGate = Completer<MomentsSettings>();
    final reading = r.loadSettings();
    await Future<void>.delayed(Duration.zero);
    await r.setBlockedViewer('peer', true);
    gate.complete(old);
    await reading;
    expect(r.privacySelections.blockedViewerIds, ['peer']);
    expect(r.settings!.version, 1);
  });
  test(
      'server can repair corrupt cache; failed network preserves confirmed cache',
      () async {
    final api = RemotePrivacyApi()..blocked.add('peer');
    final store = MemoryPrivacySelectionStore()..failLoad = true;
    final r = repository(api, store);
    addTearDown(r.dispose);
    await r.loadPrivacySelections();
    expect(r.privacySelections.blockedViewerIds, ['peer']);
    store.failLoad = false;
    api.failRead = true;
    await expectLater(
        r.loadPrivacySelections(force: true), throwsA(isA<MomentsException>()));
    expect(r.privacySelections.blockedViewerIds, ['peer']);
  });
  test(
      'failed snapshot persistence retries without issuing another server mutation',
      () async {
    final api = RemotePrivacyApi();
    final store = MemoryPrivacySelectionStore()..failApply = true;
    final r = repository(api, store);
    addTearDown(r.dispose);
    await r.setBlockedViewer('peer', true);
    expect(r.privacySelections.blockedViewerIds, ['peer']);
    expect(r.privacyPersistenceError, isNotNull);
    store.failApply = false;
    await r.retryPrivacyPersistence();
    expect(api.version, 1);
    expect(r.privacyPersistenceError, isNull);
    expect(
        (await store.load(ownerUserId: 'me', baseUrl: 'test')).blockedViewerIds,
        ['peer']);
  });
  test('old account response cannot populate a new account', () async {
    final api = RemotePrivacyApi();
    var owner = 'first';
    final r =
        repository(api, MemoryPrivacySelectionStore(), owner: () => owner);
    addTearDown(r.dispose);
    final gate = api.readGate = Completer<MomentsSettings>();
    final reading = r.loadSettings();
    final assertion = expectLater(reading, throwsA(isA<MomentsException>()));
    await Future<void>.delayed(Duration.zero);
    owner = 'second';
    r.sessionScope;
    gate.complete(MomentsSettings.fromJson({
      'privacyListsLoaded': true,
      'blockedViewerIDs': ['private']
    }));
    await assertion;
    expect(r.privacySelections.blockedViewerIds, isEmpty);
    expect(r.settings, isNull);
  });
  test('old account mutation completion cannot suppress new account hydration',
      () async {
    final api = RemotePrivacyApi();
    var owner = 'first';
    final r =
        repository(api, MemoryPrivacySelectionStore(), owner: () => owner);
    addTearDown(r.dispose);
    await r.loadPrivacySelections();
    final writeGate = api.writeGate = Completer<MomentsSettings>();
    final writing = r.setBlockedViewer('private-first', true);
    final failedOld = expectLater(writing, throwsA(isA<MomentsException>()));
    while (!api.writeStarted) {
      await Future<void>.delayed(Duration.zero);
    }
    owner = 'second';
    final readGate = api.readGate = Completer<MomentsSettings>();
    final reading = r.loadSettings();
    await Future<void>.delayed(Duration.zero);
    writeGate.complete(MomentsSettings.fromJson({
      'privacyListsLoaded': true,
      'blockedViewerIDs': ['private-first'],
      'version': 1
    }));
    await failedOld;
    readGate.complete(MomentsSettings.fromJson({
      'privacyListsLoaded': true,
      'blockedViewerIDs': ['private-second'],
      'version': 1
    }));
    await reading;
    expect(r.privacySelections.blockedViewerIds, ['private-second']);
  });

  test(
      'wire contract distinguishes old absent lists and authoritative empty, parses int64 string',
      () {
    final old = MomentsSettings.fromJson({});
    expect(old.blockedViewersLoaded, isFalse);
    final empty = MomentsSettings.fromJson(
        {'privacyListsLoaded': true, 'updatedAt': '1700000000123'});
    expect(empty.blockedViewersLoaded && empty.hiddenAuthorsLoaded, isTrue);
    expect(empty.blockedViewerIds, isEmpty);
    expect(empty.updatedAt, 1700000000123);
  });
}
