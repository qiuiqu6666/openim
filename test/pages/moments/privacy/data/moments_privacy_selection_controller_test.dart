import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/privacy/data/moments_privacy_selection_controller.dart';

const _base = 'https://business.example';
MomentsPrivacyChange _change(String id,
        {bool enabled = true,
        MomentsPrivacySelectionKind kind =
            MomentsPrivacySelectionKind.blockedViewer}) =>
    MomentsPrivacyChange(kind: kind, userId: id, enabled: enabled);

class _Store extends MomentsPrivacySelectionStore {
  final records = <String, MomentsPrivacySelections>{};
  final writes = <List<MomentsPrivacyChange>>[];
  int reads = 0;
  Future<MomentsPrivacySelections> Function(String, String)? readWork;
  Future<MomentsPrivacySelections> Function(
      String, String, List<MomentsPrivacyChange>)? writeWork;
  static String key(String owner, String base) =>
      MomentsPrivacySelectionStore.storageKey(
          ownerUserId: owner, baseUrl: base);
  @override
  Future<MomentsPrivacySelections> load(
      {required String ownerUserId, required String baseUrl}) async {
    reads++;
    return readWork?.call(ownerUserId, baseUrl) ??
        records[key(ownerUserId, baseUrl)] ??
        MomentsPrivacySelections.empty;
  }

  @override
  Future<MomentsPrivacySelections> apply(
      {required String ownerUserId,
      required String baseUrl,
      required List<MomentsPrivacyChange> changes}) async {
    writes.add(List.of(changes));
    final result = writeWork != null
        ? await writeWork!(ownerUserId, baseUrl, changes)
        : (records[key(ownerUserId, baseUrl)] ?? MomentsPrivacySelections.empty)
            .apply(changes);
    records[key(ownerUserId, baseUrl)] = result;
    return result;
  }
}

class _FinishingStore extends MomentsPrivacySelectionStore {
  final first = Completer<MomentsPrivacySelections>();
  MomentsPrivacySelections saved = MomentsPrivacySelections.empty;
  int calls = 0;
  @override
  Future<MomentsPrivacySelections> apply(
      {required String ownerUserId,
      required String baseUrl,
      required List<MomentsPrivacyChange> changes}) {
    calls++;
    if (calls == 1) return first.future;
    saved = saved.apply(changes);
    return Future.value(saved);
  }
}

void main() {
  late _Store store;
  late MomentsPrivacySelectionController controller;
  setUp(() {
    store = _Store();
    controller = MomentsPrivacySelectionController(store: store);
  });

  test('loading deduplicates, caches, and only force reads a changed snapshot',
      () async {
    final gate = Completer<MomentsPrivacySelections>();
    store.readWork = (_, __) => gate.future;
    final first = controller.load(ownerUserId: 'me', baseUrl: _base);
    final second = controller.load(ownerUserId: 'me', baseUrl: _base);
    expect(store.reads, 1);
    gate.complete(MomentsPrivacySelections(blockedViewerIds: ['one']));
    await Future.wait([first, second]);
    expect(controller.loaded, isTrue);
    expect(controller.value.blockedViewerIds, ['one']);
    store.readWork = null;
    store.records[_Store.key('me', _base)] =
        MomentsPrivacySelections(blockedViewerIds: ['two']);
    await controller.load(ownerUserId: 'me', baseUrl: _base);
    expect(store.reads, 1);
    expect(controller.value.blockedViewerIds, ['one']);
    await controller.load(ownerUserId: 'me', baseUrl: _base, force: true);
    expect(store.reads, 2);
    expect(controller.value.blockedViewerIds, ['two']);
  });

  test('read completion after reset cannot populate another owner snapshot',
      () async {
    final gate = Completer<MomentsPrivacySelections>();
    store.readWork = (owner, _) => owner == 'old'
        ? gate.future
        : Future.value(MomentsPrivacySelections(hiddenAuthorIds: ['new-id']));
    final previous = controller.load(ownerUserId: 'old', baseUrl: _base);
    controller.reset();
    expect(controller.loaded, isFalse);
    expect(controller.value.blockedViewerIds, isEmpty);
    await controller.load(ownerUserId: 'new', baseUrl: _base);
    gate.complete(MomentsPrivacySelections(blockedViewerIds: ['old-id']));
    await previous;
    expect(controller.value.blockedViewerIds, isEmpty);
    expect(controller.value.hiddenAuthorIds, ['new-id']);
    expect(controller.persistenceError, isNull);
  });

  test(
      'captured old writes finish under the old key and do not mutate new cache',
      () async {
    final gate = Completer<MomentsPrivacySelections>();
    store.writeWork = (owner, _, changes) => owner == 'old'
        ? gate.future
        : Future.value(MomentsPrivacySelections.empty.apply(changes));
    final previous = controller.confirm(
        ownerUserId: 'old', baseUrl: _base, change: _change('old-id'));
    expect(controller.value.blockedViewerIds, ['old-id']);
    controller.reset();
    await controller.confirm(
        ownerUserId: 'new',
        baseUrl: 'https://new.example',
        change:
            _change('new-id', kind: MomentsPrivacySelectionKind.hiddenAuthor));
    gate.complete(MomentsPrivacySelections(blockedViewerIds: ['old-id']));
    await previous;
    expect(controller.value.blockedViewerIds, isEmpty);
    expect(controller.value.hiddenAuthorIds, ['new-id']);
    expect(
        store.records[_Store.key('old', _base)]!.blockedViewerIds, ['old-id']);
    expect(
        store
            .records[_Store.key('new', 'https://new.example')]!.hiddenAuthorIds,
        ['new-id']);
  });

  test('same-owner reset reloads confirmed records across a new login token',
      () async {
    await controller.confirm(
        ownerUserId: 'me', baseUrl: _base, change: _change('one'));
    controller.reset();
    await controller.load(ownerUserId: 'me', baseUrl: _base);
    expect(controller.value.blockedViewerIds, ['one']);
    expect(store.records, hasLength(1));
  });

  test('concurrent confirmations update memory immediately and drain in order',
      () async {
    final gate = Completer<MomentsPrivacySelections>();
    var firstWrite = true;
    store.writeWork = (owner, base, changes) async {
      if (firstWrite) {
        firstWrite = false;
        return gate.future;
      }
      return store.records[_Store.key(owner, base)]!.apply(changes);
    };
    final first = controller.confirm(
        ownerUserId: 'me', baseUrl: _base, change: _change('one'));
    final second = controller.confirm(
        ownerUserId: 'me',
        baseUrl: _base,
        change: _change('two', kind: MomentsPrivacySelectionKind.hiddenAuthor));
    expect(controller.value.blockedViewerIds, ['one']);
    expect(controller.value.hiddenAuthorIds, ['two']);
    expect(store.writes, hasLength(1));
    gate.complete(MomentsPrivacySelections(blockedViewerIds: ['one']));
    await Future.wait([first, second]);
    expect(store.writes, hasLength(2));
    expect(controller.value.blockedViewerIds, ['one']);
    expect(controller.value.hiddenAuthorIds, ['two']);
  });

  test(
      'a later opposite confirmation stays visible while an older write finishes',
      () async {
    final gate = Completer<MomentsPrivacySelections>();
    var firstWrite = true;
    store.writeWork = (owner, base, changes) async {
      if (firstWrite) {
        firstWrite = false;
        return gate.future;
      }
      return store.records[_Store.key(owner, base)]!.apply(changes);
    };
    final first = controller.confirm(
        ownerUserId: 'me', baseUrl: _base, change: _change('one'));
    final second = controller.confirm(
        ownerUserId: 'me',
        baseUrl: _base,
        change: _change('one', enabled: false));
    expect(controller.value.blockedViewerIds, isEmpty);
    gate.complete(MomentsPrivacySelections(blockedViewerIds: ['one']));
    await Future.wait([first, second]);
    expect(controller.value.blockedViewerIds, isEmpty);
    expect(store.records[_Store.key('me', _base)]!.blockedViewerIds, isEmpty);
  });

  test(
      'disk failure retains server confirmation and retry only persists locally',
      () async {
    store.writeWork = (_, __, ___) async => throw StateError('disk full');
    await controller.confirm(
        ownerUserId: 'me', baseUrl: _base, change: _change('one'));
    expect(controller.value.blockedViewerIds, ['one']);
    expect(controller.loaded, isTrue);
    expect(controller.persistenceError, isA<StateError>());
    store.writeWork = null;
    await controller.persistPending(ownerUserId: 'me', baseUrl: _base);
    expect(controller.value.blockedViewerIds, ['one']);
    expect(controller.persistenceError, isNull);
    expect(store.writes, hasLength(2));
    expect(store.records[_Store.key('me', _base)]!.blockedViewerIds, ['one']);
    await controller.persistPending(ownerUserId: 'me', baseUrl: _base);
    expect(store.writes, hasLength(2));
  });

  test('a confirmation in the finishing write window still starts persistence',
      () async {
    final finishing = _FinishingStore();
    final owner = MomentsPrivacySelectionController(store: finishing);
    final initial = owner.confirm(
        ownerUserId: 'me', baseUrl: _base, change: _change('one'));
    final trailing = finishing.first.future.then((_) => owner.confirm(
        ownerUserId: 'me', baseUrl: _base, change: _change('two')));
    finishing.saved = MomentsPrivacySelections(blockedViewerIds: ['one']);
    finishing.first.complete(finishing.saved);
    await Future.wait([initial, trailing]);
    expect(finishing.calls, 2);
    expect(finishing.saved.blockedViewerIds, ['one', 'two']);
    expect(owner.value.blockedViewerIds, ['one', 'two']);
  });

  test('force hydration never overwrites confirmed dirty additions or removals',
      () async {
    store.records[_Store.key('me', _base)] = MomentsPrivacySelections(
        blockedViewerIds: ['old'], hiddenAuthorIds: ['hidden']);
    await controller.load(ownerUserId: 'me', baseUrl: _base);
    store.writeWork = (_, __, ___) async => throw StateError('disk full');
    await controller.confirm(
        ownerUserId: 'me',
        baseUrl: _base,
        change: _change('old', enabled: false));
    await controller.confirm(
        ownerUserId: 'me', baseUrl: _base, change: _change('new'));
    await controller.load(ownerUserId: 'me', baseUrl: _base, force: true);
    expect(controller.value.blockedViewerIds, ['new']);
    expect(controller.value.hiddenAuthorIds, ['hidden']);
    expect(controller.persistenceError, isA<StateError>());
    store.writeWork = null;
    await controller.persistPending(ownerUserId: 'me', baseUrl: _base);
    expect(controller.persistenceError, isNull);
    expect(store.records[_Store.key('me', _base)]!.blockedViewerIds, ['new']);
  });

  test(
      'a read begun before confirmed successful writes cannot restore old data',
      () async {
    final gate = Completer<MomentsPrivacySelections>();
    store.readWork = (_, __) => gate.future;
    final previous = controller.load(ownerUserId: 'me', baseUrl: _base);
    await controller.confirm(
        ownerUserId: 'me', baseUrl: _base, change: _change('new'));
    gate.complete(MomentsPrivacySelections.empty);
    await previous;
    expect(controller.value.blockedViewerIds, ['new']);
  });

  test('failed reads preserve a prior confirmed snapshot and can recover',
      () async {
    await controller.confirm(
        ownerUserId: 'me', baseUrl: _base, change: _change('one'));
    store.readWork = (_, __) async => throw const FormatException('corrupt');
    await expectLater(
        controller.load(ownerUserId: 'me', baseUrl: _base, force: true),
        throwsFormatException);
    expect(controller.value.blockedViewerIds, ['one']);
    expect(controller.persistenceError, isA<FormatException>());
    store.readWork = null;
    await controller.load(ownerUserId: 'me', baseUrl: _base, force: true);
    expect(controller.value.blockedViewerIds, ['one']);
    expect(controller.persistenceError, isNull);
  });

  test(
      'reset also drains already confirmed queued changes under their fixed key',
      () async {
    final gate = Completer<MomentsPrivacySelections>();
    var firstWrite = true;
    store.writeWork = (owner, base, changes) async {
      if (firstWrite) {
        firstWrite = false;
        return gate.future;
      }
      return store.records[_Store.key(owner, base)]!.apply(changes);
    };
    final first = controller.confirm(
        ownerUserId: 'old', baseUrl: _base, change: _change('one'));
    final second = controller.confirm(
        ownerUserId: 'old', baseUrl: _base, change: _change('two'));
    controller.reset();
    await controller.load(ownerUserId: 'new', baseUrl: _base);
    gate.complete(MomentsPrivacySelections(blockedViewerIds: ['one']));
    await Future.wait([first, second]);
    expect(store.records[_Store.key('old', _base)]!.blockedViewerIds,
        ['one', 'two']);
    expect(controller.value.blockedViewerIds, isEmpty);
    expect(controller.persistenceError, isNull);
  });
}
