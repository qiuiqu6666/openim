import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/privacy/data/moments_privacy_selection_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'https://business.example/chat';
MomentsPrivacyChange _change(String id,
        {bool enabled = true,
        MomentsPrivacySelectionKind kind =
            MomentsPrivacySelectionKind.blockedViewer}) =>
    MomentsPrivacyChange(kind: kind, userId: id, enabled: enabled);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default shared preferences keep both confirmed lists across new stores',
      () async {
    final first = MomentsPrivacySelectionStore();
    await first.apply(ownerUserId: 'me', baseUrl: _base, changes: [
      _change('blocked'),
      _change('hidden', kind: MomentsPrivacySelectionKind.hiddenAuthor)
    ]);
    final saved = await MomentsPrivacySelectionStore()
        .load(ownerUserId: 'me', baseUrl: _base);
    expect(saved.blockedViewerIds, ['blocked']);
    expect(saved.hiddenAuthorIds, ['hidden']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), hasLength(1));
    final snapshot =
        jsonDecode(prefs.getString(prefs.getKeys().single)!) as Map;
    expect(snapshot.keys.toSet(), {
      'version',
      'ownerUserId',
      'baseUrl',
      'blockedViewerIds',
      'hiddenAuthorIds'
    });
  });

  test('server and account namespaces stay separate without token keys',
      () async {
    final store = MomentsPrivacySelectionStore();
    await store
        .apply(ownerUserId: 'me', baseUrl: _base, changes: [_change('a')]);
    await store
        .apply(ownerUserId: 'other', baseUrl: _base, changes: [_change('b')]);
    await store.apply(
        ownerUserId: 'me',
        baseUrl: 'https://other.example/chat',
        changes: [_change('c')]);
    expect(
        (await store.load(ownerUserId: 'me', baseUrl: _base)).blockedViewerIds,
        ['a']);
    expect(
        (await store.load(ownerUserId: 'other', baseUrl: _base))
            .blockedViewerIds,
        ['b']);
    expect(
        (await store.load(
                ownerUserId: 'me', baseUrl: 'https://other.example/chat'))
            .blockedViewerIds,
        ['c']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), hasLength(3));
  });

  test('canonical URLs converge while different origins and paths do not', () {
    String key(String base, [String owner = 'me']) =>
        MomentsPrivacySelectionStore.storageKey(
            ownerUserId: owner, baseUrl: base);
    expect(key(' HTTPS://BUSINESS.EXAMPLE:443/chat/// '), key(_base));
    expect(key('http://business.example:80/chat/'),
        key('http://business.example/chat'));
    expect(key(_base), isNot(key('http://business.example/chat')));
    expect(key(_base), isNot(key('https://business.example:444/chat')));
    expect(key(_base), isNot(key('https://business.example/Chat')));
    expect(key(' test/ '), key('test'));
    expect(key('test:a', 'b:c'), isNot(key('test:a:b', 'c')));
    expect(key(_base, 'a:b'), isNot(key(_base, 'a_b')));
    expect(() => key('', 'me'), throwsArgumentError);
    expect(() => key(_base, ''), throwsArgumentError);
    expect(
        () => key('https://name:secret@business.example'), throwsArgumentError);
  });

  test(
      'separate instances serialize same-key read-modify-write without lost IDs',
      () async {
    final first = MomentsPrivacySelectionStore();
    final second = MomentsPrivacySelectionStore();
    await Future.wait([
      first.apply(ownerUserId: 'me', baseUrl: _base, changes: [_change('one')]),
      second.apply(ownerUserId: 'me', baseUrl: _base, changes: [
        _change('two', kind: MomentsPrivacySelectionKind.hiddenAuthor)
      ]),
      first.apply(
          ownerUserId: 'me', baseUrl: _base, changes: [_change('three')]),
    ]);
    final result = await second.load(ownerUserId: 'me', baseUrl: _base);
    expect(result.blockedViewerIds, ['one', 'three']);
    expect(result.hiddenAuthorIds, ['two']);
  });

  test('ordered updates to the same target keep the final confirmed direction',
      () async {
    final store = MomentsPrivacySelectionStore();
    await Future.wait([
      store
          .apply(ownerUserId: 'me', baseUrl: _base, changes: [_change('same')]),
      store.apply(
          ownerUserId: 'me',
          baseUrl: _base,
          changes: [_change('same', enabled: false)]),
    ]);
    expect(
        (await store.load(ownerUserId: 'me', baseUrl: _base)).blockedViewerIds,
        isEmpty);
  });

  test('queued writes capture immutable owner, server and changes', () async {
    final records = <String, String>{};
    final gate = Completer<void>();
    var firstRead = true;
    final store = MomentsPrivacySelectionStore(readSnapshot: (key) async {
      if (firstRead) {
        firstRead = false;
        await gate.future;
      }
      return records[key];
    }, writeSnapshot: (key, value) async {
      records[key] = value;
      return true;
    });
    var owner = 'old';
    var base = _base;
    final changes = [_change('old-id')];
    final previous =
        store.apply(ownerUserId: owner, baseUrl: base, changes: changes);
    await Future<void>.delayed(Duration.zero);
    owner = 'new';
    base = 'https://new.example';
    changes.clear();
    await store
        .apply(ownerUserId: owner, baseUrl: base, changes: [_change('new-id')]);
    gate.complete();
    await previous;
    expect(
        (await store.load(ownerUserId: 'old', baseUrl: _base)).blockedViewerIds,
        ['old-id']);
    expect(
        (await store.load(ownerUserId: owner, baseUrl: base)).blockedViewerIds,
        ['new-id']);
  });

  test('false storage acknowledgements fail without replacing the old snapshot',
      () async {
    final records = <String, String>{};
    var writable = true;
    final store = MomentsPrivacySelectionStore(
        readSnapshot: (key) async => records[key],
        writeSnapshot: (key, value) async {
          if (!writable) return false;
          records[key] = value;
          return true;
        });
    await store
        .apply(ownerUserId: 'me', baseUrl: _base, changes: [_change('old')]);
    writable = false;
    await expectLater(
        store.apply(
            ownerUserId: 'me', baseUrl: _base, changes: [_change('new')]),
        throwsStateError);
    expect(
        (await store.load(ownerUserId: 'me', baseUrl: _base)).blockedViewerIds,
        ['old']);
  });

  test('corrupt or mismatched records never become an empty writable snapshot',
      () async {
    var writes = 0;
    for (final raw in [
      '{',
      jsonEncode({'version': 9}),
      jsonEncode({
        'version': 1,
        'ownerUserId': 'other',
        'baseUrl': _base,
        'blockedViewerIds': [],
        'hiddenAuthorIds': []
      }),
      jsonEncode({
        'version': 1,
        'ownerUserId': 'me',
        'baseUrl': _base,
        'blockedViewerIds': [1],
        'hiddenAuthorIds': []
      })
    ]) {
      final store = MomentsPrivacySelectionStore(
          readSnapshot: (_) async => raw,
          writeSnapshot: (_, __) async {
            writes++;
            return true;
          });
      await expectLater(
          store.apply(
              ownerUserId: 'me', baseUrl: _base, changes: [_change('new')]),
          throwsFormatException);
    }
    expect(writes, 0);
  });

  test('an empty change batch reads and never overwrites existing records',
      () async {
    var writes = 0;
    final store = MomentsPrivacySelectionStore(
        readSnapshot: (_) async => null,
        writeSnapshot: (_, __) async {
          writes++;
          return true;
        });
    final result =
        await store.apply(ownerUserId: 'me', baseUrl: _base, changes: []);
    expect(result.blockedViewerIds, isEmpty);
    expect(writes, 0);
  });
}
