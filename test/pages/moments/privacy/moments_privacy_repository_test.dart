import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_repository.dart';

class _PrivacyStore extends MomentsPrivacySelectionStore {
  final values = <String, MomentsPrivacySelections>{};
  Completer<MomentsPrivacySelections>? loadGate;
  Completer<void>? saveGate;
  bool failSave = false;
  int saveCalls = 0;
  String _key(String owner, String server) => '$server|$owner';

  @override
  Future<MomentsPrivacySelections> load(
      {required String ownerUserId, required String baseUrl}) async {
    if (loadGate != null) return loadGate!.future;
    return values[_key(ownerUserId, baseUrl)] ?? MomentsPrivacySelections.empty;
  }

  @override
  Future<MomentsPrivacySelections> apply(
      {required String ownerUserId,
      required String baseUrl,
      required List<MomentsPrivacyChange> changes}) async {
    saveCalls++;
    if (saveGate != null) await saveGate!.future;
    if (failSave) throw StateError('Device storage unavailable');
    final key = _key(ownerUserId, baseUrl);
    final previous = values[key] ?? MomentsPrivacySelections.empty;
    final blocked = previous.blockedViewerIds.toSet();
    final hidden = previous.hiddenAuthorIds.toSet();
    for (final change in changes) {
      final ids = change.kind == MomentsPrivacySelectionKind.blockedViewer
          ? blocked
          : hidden;
      if (change.enabled) {
        ids.add(change.userId);
      } else {
        ids.remove(change.userId);
      }
    }
    return values[key] = MomentsPrivacySelections(
        blockedViewerIds: blocked.toList(), hiddenAuthorIds: hidden.toList());
  }
}

class _Api extends MomentsApi {
  final writes = <String>[];
  Object? writeError;
  Completer<MomentsSettings>? writeGate;
  int settingsCalls = 0;
  @override
  Future<MomentsCapabilities> capabilities() async =>
      MomentsCapabilities.fromJson({'supportsMoments': true});

  @override
  Future<MomentsSettings> settings() async {
    settingsCalls++;
    return MomentsSettings.fromJson({
      'visibleRangeDays': 90,
      'coverMediaID': 'existing-cover',
      'coverPath': '/moments/media/existing-cover/content',
      'version': 7,
    });
  }

  Future<MomentsSettings> _write(String kind, String id, bool enabled) async {
    writes.add('$kind|$id|$enabled');
    if (writeError != null) throw writeError!;
    if (writeGate != null) return writeGate!.future;
    // The real command can return only an acknowledgement with no settings.
    return MomentsSettings.fromJson({});
  }

  @override
  Future<MomentsSettings> setBlockedViewer(String id, bool enabled) =>
      _write('blocked', id, enabled);

  @override
  Future<MomentsSettings> setHiddenAuthor(String id, bool enabled) =>
      _write('hidden', id, enabled);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _PrivacyStore store;
  late _Api api;
  late MomentsRepository repository;
  var account = 'account-a';
  var server = 'https://chat.example';
  setUp(() {
    account = 'account-a';
    server = 'https://chat.example';
    store = _PrivacyStore();
    api = _Api();
    repository = MomentsRepository(
        api: api,
        userIdProvider: () => account,
        environmentProvider: () => server,
        privacySelectionStore: store,
        friendLoader: () async => [],
        subscribeToSdk: false);
  });
  tearDown(() => repository.dispose());

  test('empty local selection loads without requesting settings', () async {
    await repository.loadPrivacySelections();
    expect(repository.privacySelectionsLoaded, isTrue);
    expect(repository.privacySelections.blockedViewerIds, isEmpty);
    expect(repository.privacySelections.hiddenAuthorIds, isEmpty);
    expect(api.settingsCalls, 0);
  });

  test('minimal acknowledgements preserve range, cover and settings version',
      () async {
    await repository.loadSettings();
    await repository.setBlockedViewer('friend-im-id', true);
    await repository.setHiddenAuthor('other-im-id', true);
    expect(repository.privacySelections.blockedViewerIds, ['friend-im-id']);
    expect(repository.privacySelections.hiddenAuthorIds, ['other-im-id']);
    expect(repository.settings!.visibleRangeDays, 90);
    expect(repository.settings!.coverMediaId, 'existing-cover');
    expect(repository.settings!.version, 7);
    expect(
        api.writes, ['blocked|friend-im-id|true', 'hidden|other-im-id|true']);
  });

  test('settings refresh never erases locally confirmed selections', () async {
    await repository.setBlockedViewer('friend', true);
    await repository.setHiddenAuthor('other', true);
    await repository.loadSettings();
    await repository.loadPrivacySelections(force: true);
    expect(repository.privacySelections.blockedViewerIds, ['friend']);
    expect(repository.privacySelections.hiddenAuthorIds, ['other']);
  });

  test('cancellation is sent even for a friend absent from the local record',
      () async {
    await repository.setBlockedViewer('previous-device-friend', false);
    await repository.setHiddenAuthor('previous-device-author', false);
    expect(api.writes, [
      'blocked|previous-device-friend|false',
      'hidden|previous-device-author|false'
    ]);
    expect(repository.privacySelections.blockedViewerIds, isEmpty);
    expect(repository.privacySelections.hiddenAuthorIds, isEmpty);
  });

  test('a failed later command preserves earlier confirmed members', () async {
    await repository.setBlockedViewer('first', true);
    api.writeError = const MomentsException('Rejected');
    await expectLater(repository.setBlockedViewer('second', true),
        throwsA(isA<MomentsException>()));
    expect(repository.privacySelections.blockedViewerIds, ['first']);
    expect(store.saveCalls, 1);
  });

  test(
      'unknown result does not change confirmed membership and retries same intent',
      () async {
    await repository.setHiddenAuthor('friend', true);
    api.writeError = const MomentsException('Timed out', unknownResult: true);
    await expectLater(repository.setHiddenAuthor('friend', false),
        throwsA(isA<MomentsException>()));
    expect(repository.privacySelections.hiddenAuthorIds, ['friend']);
    api.writeError = null;
    await repository.setHiddenAuthor('friend', false);
    expect(repository.privacySelections.hiddenAuthorIds, isEmpty);
    expect(api.writes,
        ['hidden|friend|true', 'hidden|friend|false', 'hidden|friend|false']);
  });

  test('new account and server cannot inherit local selections', () async {
    await repository.setBlockedViewer('friend-a', true);
    account = 'account-b';
    await repository.loadPrivacySelections();
    expect(repository.privacySelections.blockedViewerIds, isEmpty);
    await repository.setHiddenAuthor('friend-b', true);
    server = 'https://another-chat.example';
    await repository.loadPrivacySelections();
    expect(repository.privacySelections.hiddenAuthorIds, isEmpty);
    account = 'account-a';
    server = 'https://chat.example';
    await repository.loadPrivacySelections();
    expect(repository.privacySelections.blockedViewerIds, ['friend-a']);
    expect(repository.privacySelections.hiddenAuthorIds, isEmpty);
  });

  test('renewing session retains the same account and server record', () async {
    await repository.setHiddenAuthor('friend', true);
    repository.resetSession();
    expect(repository.privacySelectionsLoaded, isFalse);
    await repository.loadPrivacySelections();
    expect(repository.privacySelections.hiddenAuthorIds, ['friend']);
  });

  test('a late operation cannot populate a switched account', () async {
    await repository.loadPrivacySelections();
    api.writeGate = Completer<MomentsSettings>();
    final write = repository.setBlockedViewer('old-account-friend', true);
    final assertion = expectLater(write, throwsA(isA<MomentsException>()));
    await Future<void>.delayed(Duration.zero);
    account = 'account-b';
    await repository.loadPrivacySelections();
    api.writeGate!.complete(const MomentsSettings());
    await assertion;
    expect(repository.privacySelections.blockedViewerIds, isEmpty);
    expect(store.saveCalls, 0);
  });

  test('local persistence retry never repeats an acknowledged remote command',
      () async {
    store.failSave = true;
    await repository.setBlockedViewer('friend', true);
    expect(repository.privacySelections.blockedViewerIds, ['friend']);
    expect(repository.privacyPersistenceError, isNotNull);
    expect(api.writes, ['blocked|friend|true']);
    store.failSave = false;
    await repository.retryPrivacyPersistence();
    expect(repository.privacyPersistenceError, isNull);
    expect(api.writes, ['blocked|friend|true']);
    repository.resetSession();
    await repository.loadPrivacySelections();
    expect(repository.privacySelections.blockedViewerIds, ['friend']);
  });

  test(
      'remote confirmation invalidates old content before local storage finishes',
      () async {
    const post = MomentPost(
        momentId: 'old-content', author: MomentUser(userId: 'friend'));
    await repository.loadPrivacySelections();
    repository.feedState.items = [post];
    repository.applyPost(post);
    expect(repository.postById('old-content'), isNotNull);
    store.saveGate = Completer<void>();
    final write = repository.setHiddenAuthor('friend', true);
    while (store.saveCalls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(repository.privacySelections.hiddenAuthorIds, ['friend']);
    expect(repository.feedState.items, isEmpty);
    expect(repository.postById('old-content'), isNull);
    store.saveGate!.complete();
    await write;
  });
}
