import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_api.dart';

void main() {
  test('authorized media redirects to CDN without forwarding the login token',
      () async {
    final business = Dio();
    final cdn = Dio();
    addTearDown(() {
      business.close();
      cdn.close();
    });
    var location = 'https://oss.99chat.vip/moments/new.jpg';
    var token = 'login-token';
    var switchAccount = false;
    var cdnCalls = 0;
    business.interceptors
        .add(InterceptorsWrapper(onRequest: (request, handler) {
      expect(request.headers['token'], token);
      expect(request.followRedirects, false);
      handler.resolve(Response<List<int>>(
          requestOptions: request,
          statusCode: 302,
          data: [],
          headers: Headers.fromMap({
            'location': [location]
          })));
    }));
    cdn.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      cdnCalls++;
      expect(request.uri.host, 'oss.99chat.vip');
      expect(
          request.headers.keys.map((key) => key.toLowerCase()),
          isNot(anyOf(contains('token'), contains('authorization'),
              contains('cookie'))));
      expect(request.followRedirects, false);
      if (switchAccount) token = 'new-account';
      handler.resolve(Response<List<int>>(
          requestOptions: request, statusCode: 200, data: [1, 2, 3]));
    }));
    final api = MomentsApi(
        client: business,
        mediaClient: cdn,
        baseUrl: 'https://business.example',
        tokenProvider: () => token);
    const media = MomentMedia(mediaId: 'image');
    expect(await api.downloadMedia(media), [1, 2, 3]);
    for (final invalid in [
      'https://oss.99chat.vip.evil.test/a',
      'http://oss.99chat.vip/a',
      'https://user@oss.99chat.vip/a',
      'https://oss.99chat.vip:8443/a',
      'https://99chat-1416337673.cos.ap-hongkong.myqcloud.com/a',
    ]) {
      location = invalid;
      await expectLater(
          api.downloadMedia(media), throwsA(isA<MomentsException>()));
    }
    expect(cdnCalls, 1);
    location = 'https://oss.99chat.vip/moments/new.jpg';
    switchAccount = true;
    await expectLater(
        api.downloadMedia(media),
        throwsA(isA<MomentsException>()
            .having((error) => error.authRequired, 'session changed', true)));
  });
}
