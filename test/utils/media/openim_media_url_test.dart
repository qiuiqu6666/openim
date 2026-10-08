import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/utils/media/openim_media_url.dart';

void main() {
  const api = 'http://129.226.192.93:10002';
  const objectPath = '/object/sangong/'
      '3d964f1b-745f-46cd-8b68-7f06a3dac076/openim-test.png';
  const logged = 'http://127.0.0.1:10002$objectPath'
      '?height=960&width=960&type=image';

  group('OpenIMMediaUrl.resolve', () {
    test('resolves historical Sangong XLSX downloads through the public API', () {
      const path = '/object/sangong-go/report.xlsx';
      expect(OpenIMMediaUrl.resolve('http://127.0.0.1:10002$path',
          imApiUrl: api), '$api$path');
    });

    test('corrects the logged Sangong object URL through the IM API', () {
      expect(OpenIMMediaUrl.resolve(logged, imApiUrl: api),
          '$api$objectPath?height=960&width=960&type=image');
    });

    test('recognizes localhost, the IPv4 loopback range and IPv6 loopback', () {
      for (final host in [
        'localhost',
        'LOCALHOST.',
        '127.0.0.1',
        '127.42.8.9',
        '[::1]',
        '[0:0:0:0:0:0:0:1]',
      ]) {
        expect(
            OpenIMMediaUrl.resolve('http://$host:10002$objectPath',
                imApiUrl: api),
            '$api$objectPath',
            reason: host);
      }
    });

    test('preserves the API deployment prefix and avoids a duplicate prefix',
        () {
      const base = 'https://im.test/api/';
      for (final path in [objectPath, '/api$objectPath']) {
        expect(
            OpenIMMediaUrl.resolve('http://127.0.0.1:10002$path',
                imApiUrl: base),
            'https://im.test/api$objectPath');
      }
      expect(
          OpenIMMediaUrl.resolve(logged,
              imApiUrl: 'https://im.test:8443/gateway/api'),
          'https://im.test:8443/gateway/api$objectPath'
          '?height=960&width=960&type=image');
    });

    test('keeps raw path, duplicate query keys, escapes, plus and fragment',
        () {
      const path = '/object/bucket/key%2fname%20with%20space.png';
      const suffix = '?filter=a%2fb&filter=a+b&empty=&encoded=%252F#view%2f1';
      expect(
          OpenIMMediaUrl.resolve('http://127.0.0.1:10002$path$suffix',
              imApiUrl: 'https://im.test/api'),
          'https://im.test/api$path$suffix');
    });

    test('leaves external CDN and non-object URLs exactly unchanged', () {
      for (final value in [
        'https://CDN.test$objectPath?x=a%2fb&x=a+b#view',
        'http://129.226.192.93:10002$objectPath',
        'http://127.0.0.1:10002/users/avatar.png',
        'http://127.0.0.1:10002/object-other/a.png',
        'http://127.0.0.1:10002/object',
        'http://127.0.0.1:10002/object/',
        'http://127.0.0.1:10002/other/object/a.png',
        'http://127.0.0.1:10002/api/api/object/a.png',
        'file:///tmp/a.png',
        '/object/a.png',
        'data:image/png;base64,a',
        '',
      ]) {
        expect(OpenIMMediaUrl.resolve(value, imApiUrl: 'https://im.test/api'),
            value);
      }
    });

    test('does not rewrite local development or invalid API destinations', () {
      for (final base in [
        'http://localhost:10002',
        'http://127.1.2.3:10002/api',
        'http://[::1]:10002/api',
        'https://user:password@im.test/api',
        'https://@im.test/api',
        'https://im.test/api?route=1',
        'https://im.test/api#fragment',
        'https://im.test/api/../other',
        'ftp://im.test/api',
        'not a URL',
        '',
      ]) {
        expect(OpenIMMediaUrl.resolve(logged, imApiUrl: base), logged,
            reason: base);
      }
    });

    test('invalid base and source ports return unchanged without throwing', () {
      for (final port in [
        'not-a-port',
        '-1',
        '0',
        '65536',
        '9999999999999999999999999999999999999999',
        '',
      ]) {
        expect(
            OpenIMMediaUrl.resolve(logged,
                imApiUrl: 'https://im.test:$port/api'),
            logged,
            reason: 'invalid destination port $port');
        final source = 'http://127.0.0.1:$port$objectPath';
        expect(OpenIMMediaUrl.resolve(source, imApiUrl: api), source,
            reason: 'invalid source port $port');
        expect(
            OpenIMMediaUrl.thumbnail(source, width: 960, height: 960), source);
      }
    });

    test('does not rewrite malformed, credentialed or traversal URLs', () {
      for (final value in [
        'http://user:password@127.0.0.1:10002$objectPath',
        'http://@127.0.0.1:10002$objectPath',
        'http://127.0.0.1:10002/object/a%zz.png',
        'http://127.0.0.1:10002/object/../private.png',
        'http://127.0.0.1:10002/object/%2e%2e/private.png',
        'http://127.0.0.1:10002/object/%252e%252e/private.png',
        'http://127.0.0.1:10002/object/a%2f..%2fb.png',
        'http://127.0.0.1:10002/object/a\\b.png',
        'http://127.0.0.1:10002/object//a.png',
      ]) {
        expect(OpenIMMediaUrl.resolve(value, imApiUrl: api), value);
      }
    });
  });

  group('signed URLs', () {
    test('signature, credentials and expiry keys prevent any URL alteration',
        () {
      for (final key in [
        'sig',
        'sign',
        'signature',
        '%73ignature',
        'token',
        'access_token',
        'X-Amz-Signature',
        'X-Goog-Credential',
        'X-OSS-Signature',
        'AWSAccessKeyId',
        'OSSAccessKeyId',
        'Expires',
        'Policy',
        'Key-Pair-Id',
        'auth_key',
      ]) {
        final value = 'http://127.0.0.1:10002$objectPath'
            '?$key=a%2Bb+z&x=1&x=2#view';
        expect(OpenIMMediaUrl.hasSignedQuery(value), isTrue, reason: key);
        expect(OpenIMMediaUrl.resolve(value, imApiUrl: api), value);
        expect(OpenIMMediaUrl.thumbnail(value, width: 960, height: 960), value);
      }
    });

    test('query-looking fragment content is not a request signature', () {
      expect(
          OpenIMMediaUrl.hasSignedQuery('https://im.test/a#?token=1'), isFalse);
      expect(OpenIMMediaUrl.hasSignedQuery('https://im.test/a?width=960'),
          isFalse);
      expect(OpenIMMediaUrl.hasSignedQuery('https://im.test/a?SIGNATURE='),
          isTrue);
    });
  });

  group('OpenIMMediaUrl.thumbnail', () {
    test('adds or replaces only conversion parameters and preserves fragment',
        () {
      expect(
          OpenIMMediaUrl.thumbnail('http://127.0.0.1:10002$objectPath',
              width: 960, height: 960),
          logged);
      expect(
          OpenIMMediaUrl.thumbnail(
              'http://127.0.0.1:10002$objectPath'
              '?width=100&height=200&type=image&width=300#view',
              width: 360,
              height: 640),
          'http://127.0.0.1:10002$objectPath'
          '?height=640&width=360&type=image#view');
    });

    test('preserves any non-conversion query without reencoding or dropping it',
        () {
      for (final query in [
        'filter=a%2fb&filter=a+b&empty=&encoded=%252F',
        'height=100&width=100&type=image&download=1',
        'width=100&unknown=',
      ]) {
        final value = 'https://cdn.test/a.png?$query#view';
        expect(OpenIMMediaUrl.thumbnail(value, width: 960, height: 960), value);
      }
    });

    test('keeps a GIF full URL, local input and invalid dimensions unchanged',
        () {
      for (final value in [
        'http://127.0.0.1:10002/object/a.GIF?height=30&width=30&type=image#view',
        'https://cdn.test/a.gif?token=signed',
        'file:///tmp/a.png',
        '/tmp/a.png',
        'https://cdn.test/a%zz.png',
      ]) {
        expect(OpenIMMediaUrl.thumbnail(value, width: 960, height: 960), value);
      }
      expect(OpenIMMediaUrl.thumbnail(logged, width: 0, height: 960), logged);
      expect(OpenIMMediaUrl.thumbnail(logged, width: 960, height: -1), logged);
    });
  });
}
