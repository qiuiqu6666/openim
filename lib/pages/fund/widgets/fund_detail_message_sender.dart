/// Sender metadata from the SDK message, used only for names and avatars.
/// It never changes a fund order or grants access to a payment or claim.
class FundDetailMessageSender {
  const FundDetailMessageSender({
    required this.userID,
    this.nickname = '',
    this.faceURL = '',
  });

  final String userID;
  final String nickname;
  final String faceURL;

  @override
  bool operator ==(Object other) =>
      other is FundDetailMessageSender &&
      userID == other.userID &&
      nickname == other.nickname &&
      faceURL == other.faceURL;

  @override
  int get hashCode => Object.hash(userID, nickname, faceURL);
}
