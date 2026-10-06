/// Shared destination for Sangong business requests and realtime streams.
/// Current-group tenant management uses the current Chat destination instead.
/// A full /api/v1 base owns its service prefix. An empty configured base keeps
/// using Chat with the separate path prefix for existing proxy deployments.
class SangongApiConfig {
  SangongApiConfig._();

  static const baseUrl = String.fromEnvironment('SANGONG_API_BASE_URL',
      defaultValue: 'http://129.226.192.93:10008/sangong/api/v1');
  static const pathPrefix = String.fromEnvironment(
    'SANGONG_API_PATH_PREFIX',
    defaultValue: '/sangong',
  );
  static const tenantId = String.fromEnvironment('SANGONG_TENANT_ID',
      defaultValue: '@z8hFfDvVQP0x');

  /// Endpoint definitions keep their /api/v1 contract paths. A complete API
  /// base already includes that version segment, so strip it exactly once.
  static String requestPath(
      {required String baseUrl,
      required String pathPrefix,
      required String path}) {
    final basePath = Uri.parse(baseUrl).path.replaceFirst(RegExp(r'/+$'), '');
    if (basePath.endsWith('/api/v1')) {
      return path.replaceFirst(RegExp(r'^/api/v1(?=/|$)'), '');
    }
    return '$pathPrefix$path';
  }

  static String? normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(
          value, 'baseUrl', '三公 API 地址须为不含凭据、查询参数或片段的 HTTP/HTTPS 地址');
    }
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  static String normalizePathPrefix(String value) {
    final trimmed = value.trim();
    if (trimmed.contains('://') ||
        trimmed.contains('?') ||
        trimmed.contains('#') ||
        trimmed.contains('\\')) {
      throw ArgumentError.value(value, 'pathPrefix', '三公 API 前缀须为路径');
    }
    final path = trimmed.replaceAll(RegExp(r'^/+|/+$'), '');
    return path.isEmpty ? '' : '/$path';
  }
}
