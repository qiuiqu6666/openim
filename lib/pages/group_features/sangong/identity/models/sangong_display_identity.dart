class SangongDisplayIdentity {
  const SangongDisplayIdentity(
      {required this.userID,
      this.account = '',
      this.nickname = '',
      this.faceURL = ''});
  final String userID, account, nickname, faceURL;
}

/// Display never uses routing IDs as a fallback name.
String sangongDisplayName(String nickname, String userID) {
  final value = nickname.trim();
  return value.isEmpty || value == userID || value.startsWith('im_')
      ? '用户'
      : value;
}
