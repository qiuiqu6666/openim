/// Application-owned choices for an incoming call. Outgoing waiting audio is
/// intentionally outside this policy.
class IncomingCallPreferences {
  const IncomingCallPreferences({
    this.quickAnswerPopup = true,
    this.ringtoneEnabled = true,
  });

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
