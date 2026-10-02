import 'package:dio/dio.dart';

/// Convert account errors into actionable text without exposing server internals.
String securityErrorMessage(Object error,
    {required bool zh, required String fallback}) {
  String text(String chinese, String english) => zh ? chinese : english;
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return text('请求超时，请稍后重试', 'The request timed out. Please try again.');
      case DioExceptionType.connectionError:
        return text('网络连接失败，请检查网络后重试',
            'Could not connect. Check your network and retry.');
      case DioExceptionType.badResponse:
        return text('服务暂时不可用，请稍后重试',
            'The service is unavailable. Please try again later.');
      default:
        return fallback;
    }
  }
  if (error is! (int, String)) return fallback;
  final (code, reason) = error;
  if (code >= 1501 && code <= 1507) {
    return text(
        '登录已失效，请重新登录', 'Your session has expired. Please sign in again.');
  }
  if (code == 20049 && reason.startsWith('retryAfter:')) {
    final seconds = int.tryParse(reason.substring('retryAfter:'.length));
    if (seconds != null && seconds > 0) {
      return text('反馈提交过于频繁，请 $seconds 秒后再试',
          'Try submitting feedback again in $seconds seconds.');
    }
  }
  final known = <int, String>{
    20045: text('反馈不存在', 'Feedback not found.'),
    20046: text('反馈内容已变化，请重新提交', 'Feedback changed. Please submit again.'),
    20047: text('截图数量、大小或格式不符合要求', 'Invalid screenshot count, size or format.'),
    20048: text('反馈存储失败，请稍后重试', 'Could not save feedback. Please retry.'),
    20049: text(
        '反馈提交过于频繁，请稍后再试', 'Too many feedback submissions. Please try later.'),
    20005: text(
        '验证码请求过于频繁，请稍后重试', 'Too many code requests. Please try again later.'),
    20003: text('该手机号已注册，请更换号码',
        'This phone number is already registered. Use another number.'),
    20034: text('请先设置支付密码', 'Please set a payment password first.'),
    20035:
        text('支付密码错误，请重新输入', 'Incorrect payment password. Please try again.'),
    20036: text('支付密码错误次数过多，请 15 分钟后重试',
        'Too many incorrect payment passwords. Try again in 15 minutes.'),
    20037: text('支付密码已设置，请通过短信验证码修改',
        'The payment password is already set. Change it using an SMS code.'),
    20038: text('请先绑定手机号，再通过短信重置支付密码',
        'Link a phone number before resetting your payment password by SMS.'),
    20039: text('已绑定手机号，请使用修改手机号入口',
        'A phone number is already linked. Use Change Phone Number.'),
    20040: text(
        '尚未绑定手机号，请先绑定', 'No phone number is linked. Please link one first.'),
    20041: text('请通过绑定或修改手机号页面操作', 'Use the phone linking or change page.'),
  };
  if (known.containsKey(code)) return known[code]!;
  final lower = reason.toLowerCase();
  if (lower.contains('current password is wrong')) {
    return text(
        '原登录密码错误，请重新输入', 'Incorrect current login password. Please try again.');
  }
  if (lower.contains('phone number is unchanged')) {
    return text('新手机号不能与当前手机号相同',
        'The new phone number must differ from the current one.');
  }
  if (lower.contains('invitation') || reason.contains('邀请码')) {
    return text('邀请码为空或无效，请检查后重试',
        'The invitation code is missing or invalid. Check it and retry.');
  }
  if (lower.contains('code') || reason.contains('验证码')) {
    if (lower.contains('expired') || reason.contains('过期')) {
      return text('验证码已过期，请重新获取',
          'The verification code has expired. Request a new one.');
    }
    if (lower.contains('frequent') ||
        lower.contains('limit') ||
        lower.contains('repeat') ||
        reason.contains('频繁') ||
        reason.contains('重复')) {
      return text(
          '验证码请求过于频繁，请稍后重试', 'Too many code requests. Please try again later.');
    }
    return text('验证码为空或不正确，请检查后重试',
        'The verification code is missing or incorrect. Check it and retry.');
  }
  return fallback;
}
