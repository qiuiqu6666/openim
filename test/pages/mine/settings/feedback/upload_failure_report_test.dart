import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/feedback/upload_failure_report.dart';

void main() {
  test(
      'separates DNS, TLS, storage permissions, timeout and local file failures',
      () {
    for (final item in {
      'lookup private.example: no such host': 'dns',
      'x509: certificate signed by unknown authority': 'tls',
      '<Code>AccessDenied</Code>': 'storage_access_denied',
      '<Code>SignatureDoesNotMatch</Code>': 'signature_invalid',
      '<Code>RequestExpired</Code>': 'signature_expired',
      'context deadline exceeded': 'timeout',
      'not found log file': 'log_file_missing',
      'part fileSize not match': 'part_size_mismatch',
      'no space left on device': 'local_disk_full',
      'bufio.Scanner: token too long': 'log_line_too_long',
    }.entries) {
      final report = UploadFailureReport(
          PlatformException(code: '1001', message: item.key), 'attempt-1');
      expect(report.category, item.value);
      expect(report.sdkCode, '1001');
    }
  });

  test('reports the failed SDK stage without exposing native details', () {
    for (final stage in ['prepare', 'collect', 'archive', 'transfer', 'register']) {
      final report = UploadFailureReport(
          PlatformException(
              code: '10000',
              message: 'sdk_log_stage=$stage: PUT https://secret/path?token=private '
                  'connection reset by peer'),
          'attempt-stage');
      expect(report.stage, stage);
      expect(report.text, contains('stage=$stage'));
      expect(report.category, 'connection_reset');
      expect(report.text, isNot(contains('private')));
      expect(report.text, isNot(contains('secret')));
    }
    final legacy = UploadFailureReport(
        PlatformException(code: '10005', message: 'unknown failure'), 'legacy');
    expect(legacy.stage, isNull);
    final unknown = UploadFailureReport(
        PlatformException(code: '10005', message: 'sdk_log_stage=private-path'),
        'unknown');
    expect(unknown.stage, isNull);
  });

  test('copyable report excludes signed URLs, paths and credentials', () {
    final report = UploadFailureReport(
        PlatformException(
          code: '1001',
          message: 'PUT https://private.example/path?token=secret failed, '
              'status code 403, body <Code>SignatureDoesNotMatch</Code>',
          details: {
            'path': '/data/user/private/file.zip',
            'secret': 'credential'
          },
        ),
        'attempt-2');
    expect(report.httpStatus, '403');
    expect(report.text, contains('operationID=attempt-2'));
    for (final secret in [
      'private.example',
      'secret',
      '/data/',
      'credential'
    ]) {
      expect(report.text, isNot(contains(secret)));
    }
  });

  test('unknown errors stay unknown without leaking arbitrary SDK error codes',
      () {
    final report = UploadFailureReport(
        PlatformException(
            code: 'token=secret', message: 'private internal text'),
        'attempt-3');
    expect(report.category, 'unclassified');
    expect(report.sdkCode, isNull);
    expect(report.text, isNot(contains('private')));
  });
}
