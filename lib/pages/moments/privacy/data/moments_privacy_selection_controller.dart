import 'moments_privacy_selection_store.dart';
export 'moments_privacy_selection_store.dart';

class _OwnerSelections {
  _OwnerSelections(this.ownerUserId, this.baseUrl, this.key, this.generation);
  final String ownerUserId, baseUrl, key;
  final int generation;
  MomentsPrivacySelections value = MomentsPrivacySelections.empty;
  bool loaded = false;
  Object? persistenceError;
  final dirty = <MomentsPrivacyChange>[];
  List<MomentsPrivacyChange>? readOverlay;
  Future<MomentsPrivacySelections>? reading;
  Future<void>? writing;
}

/// UI-independent confirmed-record owner. Repository session guards decide
/// whether a remote response may call confirm; no network mutation happens here.
class MomentsPrivacySelectionController {
  MomentsPrivacySelectionController({MomentsPrivacySelectionStore? store})
      : _store = store ?? MomentsPrivacySelectionStore();

  final MomentsPrivacySelectionStore _store;
  _OwnerSelections? _owner;
  int _generation = 0;

  MomentsPrivacySelections get value =>
      _owner?.value ?? MomentsPrivacySelections.empty;
  bool get loaded => _owner?.loaded ?? false;
  Object? get persistenceError => _owner?.persistenceError;

  _OwnerSelections _activate(String ownerUserId, String baseUrl) {
    final server = MomentsPrivacySelectionStore.canonicalBaseUrl(baseUrl);
    final owner = ownerUserId.trim();
    final key = MomentsPrivacySelectionStore.storageKey(
        ownerUserId: owner, baseUrl: server);
    if (_owner?.key != key) {
      _owner = _OwnerSelections(owner, server, key, ++_generation);
    }
    return _owner!;
  }

  bool _current(_OwnerSelections owner) =>
      identical(_owner, owner) && owner.generation == _generation;

  Future<MomentsPrivacySelections> load(
      {required String ownerUserId,
      required String baseUrl,
      bool force = false}) {
    final owner = _activate(ownerUserId, baseUrl);
    if (owner.reading != null) return owner.reading!;
    if (owner.loaded && !force) return Future.value(owner.value);
    final overlay = <MomentsPrivacyChange>[];
    owner.readOverlay = overlay;
    final work = _load(owner, overlay);
    owner.reading = work;
    return work.whenComplete(() {
      if (identical(owner.reading, work)) owner.reading = null;
      if (identical(owner.readOverlay, overlay)) owner.readOverlay = null;
    });
  }

  Future<MomentsPrivacySelections> _load(
      _OwnerSelections owner, List<MomentsPrivacyChange> overlay) async {
    try {
      final saved = await _store.load(
          ownerUserId: owner.ownerUserId, baseUrl: owner.baseUrl);
      if (!_current(owner)) return owner.value;
      // A stale read cannot overwrite acknowledgements made while it awaited,
      // even if their writes have already completed and cleared dirty records.
      owner.value = saved.apply([...owner.dirty, ...overlay]);
      owner.loaded = true;
      if (owner.dirty.isEmpty) owner.persistenceError = null;
      return owner.value;
    } catch (error) {
      if (_current(owner)) owner.persistenceError = error;
      rethrow;
    }
  }

  Future<void> confirm(
      {required String ownerUserId,
      required String baseUrl,
      required MomentsPrivacyChange change}) async {
    final owner = _activate(ownerUserId, baseUrl);
    owner.value = owner.value.apply([change]);
    owner.loaded = true;
    owner.dirty.add(change);
    owner.readOverlay?.add(change);
    await _persist(owner);
  }

  Future<void> persistPending(
          {required String ownerUserId, required String baseUrl}) =>
      _persist(_activate(ownerUserId, baseUrl));

  Future<void> _persist(_OwnerSelections owner) {
    final existing = owner.writing;
    if (existing != null) {
      return existing.then((_) async {
        if (owner.dirty.isEmpty || owner.persistenceError != null) return;
        // A confirmation may arrive after the old worker finishes but before
        // its completion callback clears writing. Drain that trailing change.
        if (identical(owner.writing, existing)) owner.writing = null;
        await _persist(owner);
      });
    }
    if (owner.dirty.isEmpty) return Future.value();
    final work = _write(owner);
    owner.writing = work;
    return work.whenComplete(() {
      if (identical(owner.writing, work)) owner.writing = null;
    });
  }

  Future<void> _write(_OwnerSelections owner) async {
    // An already-captured old owner's disk write may finish after reset. Its
    // immutable key and state can never update the new owner's public snapshot.
    while (owner.dirty.isNotEmpty) {
      final batch = List<MomentsPrivacyChange>.of(owner.dirty);
      try {
        final saved = await _store.apply(
            ownerUserId: owner.ownerUserId,
            baseUrl: owner.baseUrl,
            changes: batch);
        owner.dirty.removeRange(0, batch.length);
        owner.value = saved.apply(owner.dirty);
        owner.loaded = true;
        owner.persistenceError = null;
      } catch (error) {
        owner.persistenceError = error;
        // The server success is retained; retry only this device's persistence.
        return;
      }
    }
  }

  void reset() {
    _generation++;
    _owner = null;
  }
}
