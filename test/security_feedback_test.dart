import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/security_feedback.dart';

void main() {
  String message(Object error) =>
      securityErrorMessage(error, zh: true, fallback: '操作失败，请重试');
  test('account errors give a specific action without exposing backend details',
      () {
    expect(message((20035, 'FundPayPasswordWrong')), '支付密码错误，请重新输入');
    expect(message((20036, 'FundPayPasswordLocked')), '支付密码错误次数过多，请 15 分钟后重试');
    expect(message((20003, 'PhoneAlreadyRegister')), '该手机号已注册，请更换号码');
    expect(message((1001, 'verification code expired')), '验证码已过期，请重新获取');
    expect(message((1001, 'current password is wrong')), '原登录密码错误，请重新输入');
    expect(message((1001, 'phone number is unchanged')), '新手机号不能与当前手机号相同');
    expect(message((1503, 'token error')), '登录已失效，请重新登录');
    expect(message((999, 'goroutine /tmp/internal.go')), '操作失败，请重试');
  });
  test('connection failures and timeouts explain how to retry', () {
    final request = RequestOptions(path: '/account/phone/change');
    expect(
        message(DioException(
            requestOptions: request, type: DioExceptionType.connectionError)),
        '网络连接失败，请检查网络后重试');
    expect(
        message(DioException(
            requestOptions: request, type: DioExceptionType.receiveTimeout)),
        '请求超时，请稍后重试');
    expect(
        securityErrorMessage((20035, 'FundPayPasswordWrong'),
            zh: false, fallback: 'Failed'),
        'Incorrect payment password. Please try again.');
  });
}
