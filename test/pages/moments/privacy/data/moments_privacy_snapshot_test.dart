import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/privacy/data/moments_privacy_selection_controller.dart';

void main() {
  test('late cache read cannot overwrite authoritative server snapshot',
      () async {
    final gate = Completer<String?>();
    final store = MomentsPrivacySelectionStore(
        readSnapshot: (_) => gate.future,
        writeSnapshot: (_, value) async => true);
    final controller = MomentsPrivacySelectionController(store: store);
    final loading = controller.load(ownerUserId: 'me', baseUrl: 'test');
    final saving = controller.synchronize(
        ownerUserId: 'me',
        baseUrl: 'test',
        snapshot: MomentsPrivacySelections(blockedViewerIds: ['server']));
    gate.complete(null);
    await Future.wait([loading, saving]);
    expect(controller.value.blockedViewerIds, ['server']);
  });
  test(
      'snapshot supersedes in-flight older persistence and retries the newest data',
      () async {
    var writes = 0;
    String? disk;
    final firstWrite = Completer<bool>();
    final store = MomentsPrivacySelectionStore(
        readSnapshot: (_) async => disk,
        writeSnapshot: (_, value) async {
          writes++;
          if (writes == 1) await firstWrite.future;
          disk = value;
          return true;
        });
    final controller = MomentsPrivacySelectionController(store: store);
    final old = controller.confirm(
        ownerUserId: 'me',
        baseUrl: 'test',
        change: const MomentsPrivacyChange(
            kind: MomentsPrivacySelectionKind.blockedViewer,
            userId: 'old',
            enabled: true));
    while (writes == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final newSnapshot = controller.synchronize(
        ownerUserId: 'me',
        baseUrl: 'test',
        snapshot: MomentsPrivacySelections(hiddenAuthorIds: ['new']));
    firstWrite.complete(true);
    await Future.wait([old, newSnapshot]);
    expect(controller.value.blockedViewerIds, isEmpty);
    expect(controller.value.hiddenAuthorIds, ['new']);
    expect(jsonDecode(disk!)['hiddenAuthorIds'], ['new']);
    expect(jsonDecode(disk!)['blockedViewerIds'], isEmpty);
  });
}
