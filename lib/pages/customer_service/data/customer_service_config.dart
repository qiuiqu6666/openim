/// The approved 99chat customer-service deployment. Build definitions may
/// override the endpoint and inbox without changing application account APIs.
class CustomerServiceConfig {
  const CustomerServiceConfig({
    this.baseUrl = const String.fromEnvironment('CUSTOMER_SERVICE_BASE_URL',
        defaultValue: 'http://129.226.192.93:8815'),
    this.inboxIdentifier = const String.fromEnvironment('INBOX_IDENTIFIER',
        defaultValue: String.fromEnvironment(
            'CUSTOMER_SERVICE_INBOX_IDENTIFIER',
            defaultValue: 'JucC6gvPuKjfzZxLtT5ftaiQ')),
  });

  final String baseUrl;
  final String inboxIdentifier;

  String get normalizedBaseUrl {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('Invalid customer service endpoint');
    }
    return uri.toString().replaceFirst(RegExp(r'/+$'), '');
  }

  Uri get cableUri {
    final uri = Uri.parse(normalizedBaseUrl);
    return uri.replace(
        scheme: uri.scheme == 'https' ? 'wss' : 'ws',
        path: '${uri.path}/cable');
  }

  String resolveMediaUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final base = Uri.parse(normalizedBaseUrl);
    final supplied = Uri.tryParse(value);
    if (supplied == null) return '';
    if (supplied.hasScheme) {
      return const ['http', 'https'].contains(supplied.scheme.toLowerCase()) &&
              supplied.host.isNotEmpty &&
              supplied.userInfo.isEmpty
          ? supplied.toString()
          : '';
    }
    if (value.startsWith('//')) return '${base.scheme}:$value';
    if (value.startsWith('${base.path}/')) {
      return base
          .replace(path: '', query: null, fragment: null)
          .resolve(value)
          .toString();
    }
    return '$normalizedBaseUrl/${value.replaceFirst(RegExp(r'^/+'), '')}';
  }
}
