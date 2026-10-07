/// Current Chat destination by default. An optional full /api/v2 base owns its
/// prefix; group identity always remains in the request path.
class SangongApiConfig {
  SangongApiConfig._();

  static const baseUrl = String.fromEnvironment('SANGONG_API_BASE_URL');
  static const pathPrefix = String.fromEnvironment(
    'SANGONG_API_PATH_PREFIX',
    defaultValue: '/sangong',
  );
  static const tenantId = String.fromEnvironment('SANGONG_TENANT_ID');

  /// A complete API base already includes the version segment.
  static String requestPath(
      {required String baseUrl,
      required String pathPrefix,
      required String path}) {
    final basePath = Uri.parse(baseUrl).path.replaceFirst(RegExp(r'/+$'), '');
    if (basePath.endsWith('/api/v2')) {
      return path.replaceFirst(RegExp(r'^/api/v2(?=/|$)'), '');
    }
    if (basePath.endsWith('/api/v1')) {
      throw ArgumentError('三公已升级为 v2，请更新服务地址');
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
