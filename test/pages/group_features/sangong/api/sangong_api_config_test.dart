import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/api/sangong_api_config.dart';

void main() {
  test('empty API base inherits the current Chat server', () {
    expect(SangongApiConfig.normalizeBaseUrl(''), isNull);
    expect(SangongApiConfig.normalizeBaseUrl('  '), isNull);
  });

  test('API base supports a server root or a deployment subpath', () {
    expect(SangongApiConfig.normalizeBaseUrl(' https://game.example/// '),
        'https://game.example');
    expect(SangongApiConfig.normalizeBaseUrl('http://127.0.0.1:8090/proxy/'),
        'http://127.0.0.1:8090/proxy');
  });

  test('API base rejects relative URLs and non-HTTP destinations', () {
    for (final value in [
      'game.example',
      '/sangong',
      'https:///sangong',
      'ws://game.example',
      'ftp://game.example',
      'https://game.example?tenant=1',
      'https://game.example#private',
    ]) {
      expect(
          () => SangongApiConfig.normalizeBaseUrl(value), throwsArgumentError,
          reason: value);
    }
  });

  test('prefix accepts nested paths and direct service deployments', () {
    expect(SangongApiConfig.normalizePathPrefix(' /proxy/sangong/// '),
        '/proxy/sangong');
    expect(SangongApiConfig.normalizePathPrefix('proxy/sangong'),
        '/proxy/sangong');
    for (final value in ['', ' ', '/', '///']) {
      expect(SangongApiConfig.normalizePathPrefix(value), '');
    }
  });

  test('prefix rejects a URL, query, or fragment', () {
    for (final value in [
      'https://game.example/sangong',
      '/sangong?tenant=1',
      '/sangong#private',
    ]) {
      expect(() => SangongApiConfig.normalizePathPrefix(value),
          throwsArgumentError,
          reason: value);
    }
  });

  test(
      'complete API base preserves endpoint paths without duplicating prefixes',
      () {
    for (final path in [
      '/api/v1/admin/session',
      '/api/v1/admin/events/stream',
      '/api/v1/me/reports/overview',
      '/api/v1/me/team/dashboard',
    ]) {
      expect(
          SangongApiConfig.requestPath(
              baseUrl: 'http://129.226.192.93:10008/sangong/api/v1',
              pathPrefix: '/sangong',
              path: path),
          path.substring('/api/v1'.length),
          reason: path);
    }
  });

  test('complete API base ignores a configured legacy path prefix', () {
    expect(
        SangongApiConfig.requestPath(
            baseUrl: 'https://game.example/deployment/api/v1',
            pathPrefix: '/legacy/proxy',
            path: '/api/v1/me/reports/overview'),
        '/me/reports/overview');
  });

  test('server root keeps the legacy proxy prefix and API version', () {
    expect(
        SangongApiConfig.requestPath(
            baseUrl: 'https://game.example',
            pathPrefix: '/proxy/sangong',
            path: '/api/v1/admin/session'),
        '/proxy/sangong/api/v1/admin/session');
  });

  test('complete base removes the API prefix only at the endpoint start', () {
    expect(
        SangongApiConfig.requestPath(
            baseUrl: 'https://game.example/api/v1',
            pathPrefix: '/sangong',
            path: '/api/v1/admin/reference/api/v1'),
        '/admin/reference/api/v1');
  });
}
