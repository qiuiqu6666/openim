import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/privacy/data/moments_privacy_selections.dart';

void main() {
  test('selection snapshots copy, normalize and protect their input lists', () {
    final supplied = [' one ', '', 'one', 'two'];
    final snapshot = MomentsPrivacySelections(blockedViewerIds: supplied);
    supplied.clear();
    expect(snapshot.blockedViewerIds, ['one', 'two']);
    expect(snapshot.hiddenAuthorIds, isEmpty);
    expect(
        () => snapshot.blockedViewerIds.add('other'), throwsUnsupportedError);
    expect(() => MomentsPrivacySelections.empty.hiddenAuthorIds.add('other'),
        throwsUnsupportedError);
  });

  test('changes update only the selected kind and honor target order', () {
    final original = MomentsPrivacySelections(
        blockedViewerIds: ['one'], hiddenAuthorIds: ['same']);
    final result = original.apply(const [
      MomentsPrivacyChange(
          kind: MomentsPrivacySelectionKind.blockedViewer,
          userId: ' same ',
          enabled: true),
      MomentsPrivacyChange(
          kind: MomentsPrivacySelectionKind.blockedViewer,
          userId: 'same',
          enabled: false),
      MomentsPrivacyChange(
          kind: MomentsPrivacySelectionKind.hiddenAuthor,
          userId: 'two',
          enabled: true),
    ]);
    expect(original.blockedViewerIds, ['one']);
    expect(original.hiddenAuthorIds, ['same']);
    expect(result.blockedViewerIds, ['one']);
    expect(result.hiddenAuthorIds, ['same', 'two']);
  });

  test('an empty resource ID cannot enter a confirmed record', () {
    expect(
        () => MomentsPrivacySelections.empty.apply(const [
              MomentsPrivacyChange(
                  kind: MomentsPrivacySelectionKind.blockedViewer,
                  userId: ' ',
                  enabled: true)
            ]),
        throwsArgumentError);
  });
}
