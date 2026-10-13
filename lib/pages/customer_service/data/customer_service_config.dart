import 'package:openim_common/openim_common.dart' show Config;

/// The approved 99chat customer-service deployment. Build definitions may
/// override the endpoint and inbox without changing application account APIs.
class CustomerServiceConfig {
  const CustomerServiceConfig({
    this.baseUrl = const String.fromEnvironment('CUSTOMER_SERVICE_BASE_URL',
        defaultValue: Config.customerServiceOriginUrl),
    this.inboxIdentifier = const String.fromEnvironment('INBOX_IDENTIFIER',
        defaultValue: String.fromEnvironment(
            'CUSTOMER_SERVICE_INBOX_IDENTIFIER',
            defaultValue: 'JucC6gvPuKjfzZxLtT5ftaiQ')),
  });

  final String baseUrl;
  final String inboxIdentifier;

  /// Stable service identity for stored contacts, independent of proxy ports.
  String get normalizedOriginBaseUrl {
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

  String get normalizedBaseUrl {
    final origin = normalizedOriginBaseUrl;
    return origin == Config.customerServiceOriginUrl
        ? Config.customerServiceForwardUrl ?? origin
        : origin;
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
    final origin = Uri.parse(normalizedOriginBaseUrl);
    final supplied = Uri.tryParse(value);
    if (supplied == null) return '';
    if (supplied.hasScheme || value.startsWith('//')) {
      final absolute =
          supplied.hasScheme ? supplied : Uri.parse('${origin.scheme}:$value');
      if (!const ['http', 'https'].contains(absolute.scheme.toLowerCase()) ||
          absolute.host.isEmpty ||
          absolute.userInfo.isNotEmpty) {
        return '';
      }
      if (base != origin &&
          absolute.scheme == origin.scheme &&
          absolute.host == origin.host &&
          absolute.port == origin.port) {
        return absolute
            .replace(scheme: base.scheme, host: base.host, port: base.port)
            .toString();
      }
      return absolute.toString();
    }
    if (value.startsWith('${base.path}/')) {
      return base
          .replace(path: '', query: null, fragment: null)
          .resolve(value)
          .toString();
    }
    return '$normalizedBaseUrl/${value.replaceFirst(RegExp(r'^/+'), '')}';
  }
}
