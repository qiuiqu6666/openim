/// Only accept group invitations from the supported link formats.
String? parseGroupQrLink(String value) {
  try {
    return _parseGroupQrLink(value);
  } on FormatException {
    return null;
  }
}

String? _parseGroupQrLink(String value) {
  final text = value.trim();
  const legacy = 'io.openim.app/joinGroup/';
  String? id;
  if (text.startsWith(legacy)) {
    id = text.substring(legacy.length);
  } else {
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != '99chat.vip' ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }
    final values = uri.queryParametersAll['group'];
    if (values == null || values.length != 1) return null;
    id = values.single;
  }
  if (id.isEmpty ||
      id == '@' ||
      id.length > 128 ||
      RegExp(r'[\s/?#&]').hasMatch(id)) {
    return null;
  }
  return id;
}
