/// Application-owned choices for an incoming call. Outgoing waiting audio is
/// intentionally outside this policy.
class IncomingCallPreferences {
  const IncomingCallPreferences({
    this.quickAnswerPopup = true,
    this.ringtoneEnabled = true,
  });

  /// Retained for settings compatibility with 99chat. In-app invitations always
  /// open the full-screen call surface; this value never selects a sheet.
  final bool quickAnswerPopup;
  final bool ringtoneEnabled;

  @override
  bool operator ==(Object other) =>
      other is IncomingCallPreferences &&
      other.quickAnswerPopup == quickAnswerPopup &&
      other.ringtoneEnabled == ringtoneEnabled;

  @override
  int get hashCode => Object.hash(quickAnswerPopup, ringtoneEnabled);
}
