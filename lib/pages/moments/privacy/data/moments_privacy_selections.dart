enum MomentsPrivacySelectionKind { blockedViewer, hiddenAuthor }

/// A single PUT/DELETE operation that the server has already confirmed.
class MomentsPrivacyChange {
  const MomentsPrivacyChange(
      {required this.kind, required this.userId, required this.enabled});

  final MomentsPrivacySelectionKind kind;
  final String userId;
  final bool enabled;
}

/// Confirmed selections on this device. This is never an ACL authority or a
/// complete remote list: GET settings does not expose either privacy list.
class MomentsPrivacySelections {
  factory MomentsPrivacySelections(
          {Iterable<String> blockedViewerIds = const [],
          Iterable<String> hiddenAuthorIds = const []}) =>
      MomentsPrivacySelections._(_ids(blockedViewerIds), _ids(hiddenAuthorIds));

  const MomentsPrivacySelections._(this.blockedViewerIds, this.hiddenAuthorIds);
  static const empty = MomentsPrivacySelections._([], []);

  final List<String> blockedViewerIds;
  final List<String> hiddenAuthorIds;

  static List<String> _ids(Iterable<String> values) => List.unmodifiable(
      values.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet());

  MomentsPrivacySelections apply(Iterable<MomentsPrivacyChange> changes) {
    final blocked = blockedViewerIds.toSet();
    final hidden = hiddenAuthorIds.toSet();
    for (final change in changes) {
      final id = change.userId.trim();
      if (id.isEmpty) throw ArgumentError.value(change.userId, 'userId');
      final target = change.kind == MomentsPrivacySelectionKind.blockedViewer
          ? blocked
          : hidden;
      if (change.enabled) {
        target.add(id);
      } else {
        target.remove(id);
      }
    }
    return MomentsPrivacySelections(
        blockedViewerIds: blocked, hiddenAuthorIds: hidden);
  }
}
