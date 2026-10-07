import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:openim_common/openim_common.dart';

import 'http/risk_feedback.dart';

var dio = Dio();

class HttpUtil {
  HttpUtil._();
  static const _sessionFeedbackOwned = 'openimSessionFeedbackOwned';

  static void init() {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      return handler.next(options); //continue
    }, onResponse: (response, handler) {
      _reportSessionError(response.requestOptions, response.data);
      return handler.next(response); // continue
    }, onError: (DioException e, handler) {
      _reportSessionError(e.requestOptions, e.response?.data);
      return handler.next(e); //continue
    }));

    dio.options.baseUrl = Config.imApiUrl;
    dio.options.connectTimeout = const Duration(seconds: 30); //30s
    dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  static String get operationID =>
      DateTime.now().millisecondsSinceEpoch.toString();

  static String businessErrorMessage(ApiResp response, {String? path}) =>
      ApiErrorMessages.business(response.errCode,
          path: path, detail: response.errDlt, message: response.errMsg);

  static ApiResp? _readResponse(dynamic body) {
    try {
      if (body is String) body = jsonDecode(body);
      if (body is! Map || !body.containsKey('errCode')) return null;
      final code = body['errCode'];
      if (code is! int && (code is! String || int.tryParse(code) == null)) {
        return null;
      }
      return ApiResp.fromJson(Map<String, dynamic>.from(body));
    } catch (_) {
      return null;
    }
  }

  static void _reportSessionError(RequestOptions request, dynamic body) {
    if (!_isCurrentToken(request.headers['token'])) return;
    final code = _readResponse(body)?.errCode;
    if (code != null && ApiErrorMessages.isSessionError(code)) {
      request.extra[_sessionFeedbackOwned] = Apis.kickoffController.hasListener;
      Apis.kickoffController.add(code);
    }
  }

  static bool _isCurrentToken(Object? token) =>
      token is String &&
      token.isNotEmpty &&
      (token == DataSp.chatToken || token == DataSp.imToken);

  /// Callers that own feedback must also check this before a fallback toast.
  /// Keep propagating the original failure; never treat silence as success.
  static bool isSilentError(Object error, {String? path}) {
    if (error is (int, String?)) {
      return RiskFeedback.isSilent(
          code: error.$1, path: path, detail: error.$2);
    }
    if (error is DioException) {
      final response = _readResponse(error.response?.data);
      if (response != null) {
        return RiskFeedback.isSilent(
          code: response.errCode,
          path: path ?? error.requestOptions.path,
          detail:
              response.errDlt.isNotEmpty ? response.errDlt : response.errMsg,
        );
      }
    }
    return false;
  }

  /// Resolve at display time, so a locale switch affects an in-flight request.
  static String errorMessage(Object error, {String? path, String? fallback}) {
    if (error is (int, String?)) {
      return ApiErrorMessages.business(error.$1,
          path: path, detail: error.$2 ?? '');
    }
    if (error is DioException) {
      final response = _readResponse(error.response?.data);
      if (response != null && response.errCode != 0) {
        return businessErrorMessage(response,
            path: path ?? error.requestOptions.path);
      }
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          ApiErrorMessages.timeout,
        DioExceptionType.connectionError => ApiErrorMessages.network,
        DioExceptionType.cancel => ApiErrorMessages.requestCancelled,
        DioExceptionType.badResponse ||
        DioExceptionType.badCertificate =>
          ApiErrorMessages.serviceUnavailable,
        _ => fallback ?? ApiErrorMessages.requestFailed,
      };
    }
    if (error is FormatException) return ApiErrorMessages.invalidResponse;
    return fallback ?? ApiErrorMessages.requestFailed;
  }

  static Future post(
    String path, {
    dynamic data,
    bool showErrorToast = true,
    Map<String, dynamic>? queryParameters,
    Options? options,
    String? requestOperationID,
    bool withoutToken = false,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    var sessionOwnsFeedback = false;
    try {
      data ??= {};
      options ??= Options();
      options.headers ??= {};
      options.headers!['operationID'] = requestOperationID ?? operationID;

      final Response<dynamic> result;
      if (withoutToken) {
        // Remove a token inherited from Dio defaults for an unauthenticated
        // request without changing authenticated requests or global headers.
        final request = options.copyWith(method: 'POST').compose(
              dio.options,
              path,
              data: data,
              queryParameters: queryParameters,
              cancelToken: cancelToken,
              onSendProgress: onSendProgress,
              onReceiveProgress: onReceiveProgress,
            );
        request.headers.removeWhere((key, _) => key.toLowerCase() == 'token');
        result = await dio.fetch<dynamic>(request);
      } else {
        result = await dio.post<dynamic>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
          onReceiveProgress: onReceiveProgress,
        );
      }
      sessionOwnsFeedback =
          result.requestOptions.extra[_sessionFeedbackOwned] == true;
      final resp = _readResponse(result.data);
      if (resp == null) throw const FormatException('Invalid API response');
      if (resp.errCode == 0) {
        return resp.data;
      } else {
        // Keep the detailed reason available to callers that own their toast.
        throw (
          resp.errCode,
          resp.errDlt.isNotEmpty ? resp.errDlt : resp.errMsg
        );
      }
    } catch (error) {
      if (error is DioException) {
        sessionOwnsFeedback =
            error.requestOptions.extra[_sessionFeedbackOwned] == true;
      }
      final response =
          error is DioException ? _readResponse(error.response?.data) : null;
      final failure = response != null && response.errCode != 0
          ? (
              response.errCode,
              response.errDlt.isNotEmpty ? response.errDlt : response.errMsg
            )
          : error;
      // The session owner displays the expiry prompt while returning to login.
      if (showErrorToast &&
          !sessionOwnsFeedback &&
          !isSilentError(failure, path: path) &&
          !(error is DioException && error.type == DioExceptionType.cancel)) {
        IMViews.showToast(errorMessage(failure, path: path));
      }
      return Future.error(failure);
    }
  }

  static Future<String> uploadImageForMinio({
    required String path,
    bool compress = true,
  }) async {
    String fileName = path.substring(path.lastIndexOf("/") + 1);

    String? compressPath;
    if (compress) {
      File? compressFile = await IMUtils.compressImageAndGetFile(File(path));
      compressPath = compressFile?.path;
      Logger.print('compressPath: $compressPath');
    }
    final bytes = await File(compressPath ?? path).readAsBytes();
    final mf = MultipartFile.fromBytes(bytes, filename: fileName);

    var formData = FormData.fromMap({
      'operationID': '${DateTime.now().millisecondsSinceEpoch}',
      'fileType': 1,
      'file': mf
    });

    var resp = await dio.post<Map<String, dynamic>>(
      "${Config.imApiUrl}/third/minio_upload",
      data: formData,
      options: Options(headers: {'token': DataSp.imToken}),
    );
    return resp.data?['data']['URL'];
  }

  static Future download(
    String url, {
    required String cachePath,
    CancelToken? cancelToken,
    Function(int count, int total)? onProgress,
  }) {
    return dio.download(
      url,
      cachePath,
      options: Options(
        receiveTimeout: const Duration(minutes: 10),
      ),
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
    );
  }

  static Future saveUrlPicture(
    String url, {
    CancelToken? cancelToken,
    Function(int count, int total)? onProgress,
    VoidCallback? onCompletion,
  }) async {
    try {
      final resolvedURL =
          OpenIMMediaUrl.resolve(url, imApiUrl: Config.imApiUrl);
      final segments = Uri.parse(resolvedURL).pathSegments;
      final name = segments.isNotEmpty && segments.last.isNotEmpty
          ? segments.last
          : 'image_${DateTime.now().millisecondsSinceEpoch}.png';
      final cachePath =
          await IMUtils.createTempFile(dir: 'picture', name: name);
      await download(
        resolvedURL,
        cachePath: cachePath,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
      await saveFileToGallerySaver(File(cachePath), name: name);
    } catch (error) {
      Logger.print('saveUrlPicture failed: $error');
      IMViews.showToast(StrRes.saveFailed);
    } finally {
      onCompletion?.call();
    }
  }

  static Future saveImage(Image image) async {
    var byteData = await image.toByteData(format: ImageByteFormat.png);
    if (byteData != null) {
      Uint8List uint8list = byteData.buffer.asUint8List();
      var result =
          await ImageGallerySaverPlus.saveImage(Uint8List.fromList(uint8list));
      if (result != null) {
        var tips = StrRes.saveSuccessfully;
        if (Platform.isAndroid) {
          final filePath = result['filePath'].split('//').last;
          tips = '${StrRes.saveSuccessfully}:$filePath';
        }
        IMViews.showToast(tips);
      }
    }
  }

  static Future saveUrlVideo(
    String url, {
    CancelToken? cancelToken,
    Function(int count, int total)? onProgress,
    VoidCallback? onCompletion,
  }) async {
    final name = url.substring(url.lastIndexOf('/') + 1);
    final cachePath = await IMUtils.createTempFile(dir: 'video', name: name);

    if (File(cachePath).existsSync()) {
      onCompletion?.call();
      return;
    }

    return download(
      url,
      cachePath: cachePath,
      cancelToken: cancelToken,
      onProgress: (int count, int total) async {
        onProgress?.call(count, total);
        if (count == total) {
          onCompletion?.call();
          final result = await ImageGallerySaverPlus.saveFile(cachePath);
          if (result != null) {
            var tips = StrRes.saveSuccessfully;
            if (Platform.isAndroid) {
              final filePath = result['filePath'].split('//').last;
              tips = '${StrRes.saveSuccessfully}:$filePath';
            }
            IMViews.showToast(tips);
          }
        }
      },
    );
  }

  static Future saveFileToGallerySaver(File file,
      {String? name, bool showTaost = true}) async {
    Future<void> save() async {
      try {
        Logger.print('saveFileToGallerySaver: ${file.path}');
        final imageBytes = await file.readAsBytes();
        final result =
            await ImageGallerySaverPlus.saveImage(imageBytes, name: name);
        if (showTaost) {
          if (result is Map && result['isSuccess'] == true) {
            IMViews.showToast(StrRes.saveSuccessfully);
          } else {
            IMViews.showToast(StrRes.saveFailed);
          }
        }
      } catch (error) {
        Logger.print('saveFileToGallerySaver failed: $error');
        if (showTaost) IMViews.showToast(StrRes.saveFailed);
      }
    }

    if (Platform.isAndroid &&
        (await DeviceInfoPlugin().androidInfo).version.sdkInt < 29) {
      Permissions.storage(save);
    } else {
      await save();
    }
  }
}
