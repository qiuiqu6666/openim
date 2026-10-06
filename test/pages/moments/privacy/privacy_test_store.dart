import 'package:openim/services/moments_repository.dart';

/// Test-only device storage, isolated by both account and business server.
class MemoryPrivacySelectionStore extends MomentsPrivacySelectionStore {
  MemoryPrivacySelectionStore(
      {MomentsPrivacySelections initial = MomentsPrivacySelections.empty,
      String ownerUserId = 'me',
      String baseUrl = 'test'}) {
    seed(ownerUserId: ownerUserId, baseUrl: baseUrl, value: initial);
  }

  final Map<String, MomentsPrivacySelections> _values = {};
  bool failLoad = false;
  bool failApply = false;
  int loads = 0;
  int applies = 0;

  void seed(
      {required String ownerUserId,
      required String baseUrl,
      required MomentsPrivacySelections value}) {
    _values[MomentsPrivacySelectionStore.storageKey(
        ownerUserId: ownerUserId, baseUrl: baseUrl)] = value;
  }

  @override
  Future<MomentsPrivacySelections> load(
      {required String ownerUserId, required String baseUrl}) async {
    ++loads;
    if (failLoad) throw StateError('Device choices could not be read');
    return _values[MomentsPrivacySelectionStore.storageKey(
            ownerUserId: ownerUserId, baseUrl: baseUrl)] ??
        MomentsPrivacySelections.empty;
  }

  @override
  Future<MomentsPrivacySelections> apply(
      {required String ownerUserId,
      required String baseUrl,
      required List<MomentsPrivacyChange> changes}) async {
    ++applies;
    if (failApply) throw StateError('Device choices could not be saved');
    final key = MomentsPrivacySelectionStore.storageKey(
        ownerUserId: ownerUserId, baseUrl: baseUrl);
    final value =
        (_values[key] ?? MomentsPrivacySelections.empty).apply(changes);
    _values[key] = value;
    return value;
  }
}
