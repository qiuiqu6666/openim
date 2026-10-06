import 'dart:io';

/// Compatibility for unsigned OpenIM object URLs emitted with a loopback host.
/// Signed grants keep their original authority and query for server correction.
class OpenIMMediaUrl {
  OpenIMMediaUrl._();

  static String resolve(String value, {required String imApiUrl}) {
    final source = _HttpUrl.read(value);
    if (source == null ||
        !_isLoopback(source.uri) ||
        hasSignedQuery(value) ||
        _unsafePath(source.path)) {
      return value;
    }
    final base = _HttpUrl.read(imApiUrl.trim());
    if (base == null ||
        _isLoopback(base.uri) ||
        base.query.isNotEmpty ||
        base.fragment.isNotEmpty ||
        _unsafePath(base.path)) {
      return value;
    }

    final prefix = base.path.replaceFirst(RegExp(r'/+$'), '');
    String path;
    if (_isObjectPath(source.path)) {
      path = '$prefix${source.path}';
    } else if (prefix.isNotEmpty &&
        source.path.startsWith(prefix) &&
        _isObjectPath(source.path.substring(prefix.length))) {
      path = source.path;
    } else {
      return value;
    }
    // Concatenate the untouched path/query/fragment, not queryParameters, so
    // duplicate keys, literal + and percent-escape spelling remain unchanged.
    return '${base.origin}$path${source.query}${source.fragment}';
  }

  static bool hasSignedQuery(String value) {
    final question = value.indexOf('?');
    final fragment = value.indexOf('#');
    if (question < 0 || (fragment >= 0 && fragment < question)) return false;
    final query =
        value.substring(question + 1, fragment >= 0 ? fragment : value.length);
    return query.split('&').any((part) {
      final key = _queryKey(part);
      return key.startsWith('x-amz-') ||
          key.startsWith('x-goog-') ||
          key.startsWith('x-oss-') ||
          _signedKeys.contains(key);
    });
  }

  static String thumbnail(String value,
      {required int width, required int height}) {
    final url = _HttpUrl.read(value);
    if (url == null ||
        width <= 0 ||
        height <= 0 ||
        _unsafePath(url.path) ||
        hasSignedQuery(value) ||
        Uri.decodeComponent(url.path).toLowerCase().endsWith('.gif')) {
      return value;
    }
    if (url.query.isNotEmpty &&
        url.query.substring(1).isNotEmpty &&
        url.query
            .substring(1)
            .split('&')
            .any((part) => !_transformKeys.contains(_queryKey(part)))) {
      return value;
    }
    return '${url.head}?height=$height&width=$width&type=image${url.fragment}';
  }

  static const _transformKeys = {'height', 'width', 'type'};
  static const _signedKeys = {
    'sig',
    'sign',
    'signature',
    'token',
    'access_token',
    'auth_token',
    'auth',
    'authorization',
    'auth_key',
    'auth-key',
    'awsaccesskeyid',
    'ossaccesskeyid',
    'googleaccessid',
    'accesskeyid',
    'security-token',
    'expires',
    'expire',
    'expiration',
    'policy',
    'key-pair-id',
  };

  static String _queryKey(String part) {
    final raw = part.split('=').first;
    try {
      return Uri.decodeQueryComponent(raw).trim().toLowerCase();
    } on FormatException {
      return raw.toLowerCase();
    }
  }

  static bool _isLoopback(Uri uri) {
    var host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (host == 'localhost') return true;
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    return InternetAddress.tryParse(host)?.isLoopback ?? false;
  }

  static bool _isObjectPath(String path) =>
      path.startsWith('/object/') && path.length > '/object/'.length;

  static bool _unsafePath(String path) {
    var decoded = path;
    // Conservatively retain malformed or ambiguous traversal paths, including
    // encoded separators/dot segments and common double-encoded variants.
    for (var pass = 0; pass < 3; pass++) {
      if (decoded.contains('\\') ||
          decoded.contains('//') ||
          decoded.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
          decoded.split('/').any((part) => part == '.' || part == '..')) {
        return true;
      }
      try {
        final next = Uri.decodeComponent(decoded);
        if (next == decoded) return false;
        decoded = next;
      } on FormatException {
        return true;
      }
    }
    return true;
  }
}

class _HttpUrl {
  _HttpUrl(
      this.uri, this.origin, this.head, this.path, this.query, this.fragment);

  final Uri uri;
  final String origin, head, path, query, fragment;

  static final _parts = RegExp(
      r'^(https?)://([^/?#]*)([^?#]*)(\?[^#]*)?(#.*)?$',
      caseSensitive: false);
  static final _invalidEscape = RegExp(r'%(?![0-9a-fA-F]{2})');

  static _HttpUrl? read(String value) {
    if (value.contains(RegExp(r'\s|\\')) || _invalidEscape.hasMatch(value)) {
      return null;
    }
    try {
      final parts = _parts.firstMatch(value);
      final uri = Uri.tryParse(value);
      if (parts == null ||
          uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          parts.group(2)!.contains('@') ||
          parts.group(2)!.endsWith(':') ||
          uri.port <= 0 ||
          uri.port > 65535) {
        return null;
      }
      final path = parts.group(3)!;
      // Read potentially lazy URI properties within the validation boundary.
      final origin = uri.origin;
      return _HttpUrl(uri, origin, '${parts.group(1)}://${parts.group(2)}$path',
          path, parts.group(4) ?? '', parts.group(5) ?? '');
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    } on StateError {
      return null;
    }
  }
}
