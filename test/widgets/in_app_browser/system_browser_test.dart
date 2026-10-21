import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/in_app_browser/in_app_browser.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _SystemBrowser extends UrlLauncherPlatform {
  @override
  get linkDelegate => null;
  bool supported = true;
  bool success = true;
  bool fail = false;
  final urls = <String>[];
  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async {
    expect(mode, PreferredLaunchMode.inAppBrowserView);
    return supported;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    expect(options.mode, PreferredLaunchMode.inAppBrowserView);
    urls.add(url);
    if (fail) throw StateError('Unavailable');
    return success;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UrlLauncherPlatform previous;
  late _SystemBrowser browser;
  setUp(() {
    previous = UrlLauncherPlatform.instance;
    browser = _SystemBrowser();
    UrlLauncherPlatform.instance = browser;
  });
  tearDown(() => UrlLauncherPlatform.instance = previous);
  test('web links use the system in-app browser without a Flutter navigator',
      () async {
    for (final url in [
      'https://example.com',
      'https://testflight.apple.com/join/abc'
    ]) {
      expect(await openInAppBrowser(Uri.parse(url)), isTrue);
    }
    expect(browser.urls, hasLength(2));
  });
  test('unsupported mode does not fall back to external or custom browser',
      () async {
    browser.supported = false;
    expect(await openSystemBrowser(Uri.parse('https://example.com')),
        SystemBrowserOpenResult.unavailable);
    expect(await openInAppBrowser(Uri.parse('https://example.com')), isFalse);
    expect(browser.urls, isEmpty);
  });
  test('launch errors and rejection return failure', () async {
    browser.success = false;
    expect(await openSystemBrowser(Uri.parse('https://example.com')),
        SystemBrowserOpenResult.failed);
    expect(await openInAppBrowser(Uri.parse('https://example.com')), isFalse);
    browser.fail = true;
    expect(await openInAppBrowser(Uri.parse('https://example.com')), isFalse);
  });
  test('invalid links are never launched', () async {
    for (final url in [
      'file:///secret',
      'javascript:alert(1)',
      'https://user:pass@example.com',
      'https:'
    ]) {
      expect(await openSystemBrowser(Uri.parse(url)),
          SystemBrowserOpenResult.invalidLink);
      expect(await openInAppBrowser(Uri.parse(url)), isFalse);
    }
    expect(browser.urls, isEmpty);
  });
}
