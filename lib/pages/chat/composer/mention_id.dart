/// Matches an ID after @ without treating the @ in an email address as a link.
const mentionIDPattern = r'(?<![\w.])@[A-Za-z0-9_#-]{2,64}(?![\w#-])';

List<String> mentionIDCandidates(String id) {
  final value = id.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
  final bare = value.startsWith('@') ? value.substring(1) : value;
  return value.startsWith('@') ? ['@$bare', bare] : [bare, '@$bare'];
}
