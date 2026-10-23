/// Public recipient profile snapshot for presentation, never payment authority.
class FundMessageRecipient {
  const FundMessageRecipient({
    required this.userID,
    this.nickname = '',
    this.faceURL = '',
  });

  final String userID;
  final String nickname;
  final String faceURL;

  static FundMessageRecipient? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = value['userID'];
    if (id is! String || id.trim().isEmpty || id.length > 128) return null;
    final name = value['nickname'];
    final rawURL = value['faceURL'];
    final url = rawURL is String && rawURL.length <= 2048 ? rawURL.trim() : '';
    final uri = Uri.tryParse(url);
    final validURL = uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
    return FundMessageRecipient(
      userID: id.trim(),
      nickname: name is String && name.runes.length <= 256 ? name.trim() : '',
      faceURL: validURL ? url : '',
    );
  }
}
