import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:video_player/video_player.dart';

Map<String, dynamic> liveDTO(
        {String id = 'live-1',
        String status = 'AUTHORIZED',
        int version = 1}) =>
    {
      'liveSessionId': id,
      'groupId': 'group#1',
      'status': status,
      'version': version,
      'roomName': '每日直播',
      'description': '和大家边看边聊',
      'anchorUserId': 'anchor',
      if (status == 'SCHEDULED')
        'scheduledStartAt': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
    };
LiveSession liveSession(
        {LiveStatus status = LiveStatus.authorized, int version = 1}) =>
    LiveSession.fromJson(
        liveDTO(status: status.name.toUpperCase(), version: version));

class LiveTransport implements HttpClientAdapter {
  LiveTransport(this.handler);
  final FutureOr<Map<String, dynamic>> Function(RequestOptions) handler;
  final requests = <RequestOptions>[];
  int status = 200;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    Map<String, dynamic> response;
    try {
      response = await handler(options);
    } catch (error) {
      if (error is DioException) rethrow;
      throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: error);
    }
    return ResponseBody.fromString(jsonEncode(response), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
  GroupFeatureApi api({String Function()? token}) {
    final dio = Dio();
    dio.httpClientAdapter = this;
    return GroupFeatureApi(
        client: dio,
        baseUrl: 'https://example.test',
        tokenProvider: token ?? () => 'chat-token',
        userProvider: () => 'self');
  }
}

GroupFeatureContext liveContext(GroupFeatureApi api,
        {bool Function()? current,
        bool Function()? capabilitiesCurrent,
        GroupLiveCapabilities? permissions,
        ValueChanged<Map<String, dynamic>>? onFeaturesChanged,
        GroupFeatures features = const GroupFeatures(),
        Stream<Map<String, dynamic>> events = const Stream.empty()}) =>
    GroupFeatureContext(
        groupID: 'group#1',
        groupName: '直播群',
        currentUserID: 'self',
        api: api,
        features: features,
        capabilities: GroupFeatureCapabilities(
            live: permissions ??
                const GroupLiveCapabilities(
                    canConfigure: true,
                    canManage: true,
                    canPush: true,
                    canTip: true,
                    raw: {
                      'tipCurrencies': ['USDT', 'TRX', 'BI99']
                    })),
        sessionCurrent: current ?? () => true,
        capabilitiesCurrent: capabilitiesCurrent ?? () => true,
        onFeaturesChanged: onFeaturesChanged ?? (_) {},
        events: events);

class TestLiveVideo extends VideoPlayerController {
  TestLiveVideo(super.uri, {this.initialized}) : super.networkUrl();
  final Completer<void>? initialized;
  int plays = 0, pauses = 0, closes = 0;
  @override
  Future<void> initialize() async {
    await initialized?.future;
    value = VideoPlayerValue(
        duration: Duration.zero,
        isInitialized: true,
        size: const Size(1280, 720));
  }

  @override
  Future<void> play() async {
    plays++;
    value =
        value.copyWith(isPlaying: true, position: const Duration(seconds: 1));
  }

  @override
  Future<void> pause() async {
    pauses++;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }

  @override
  Future<void> dispose() async {
    closes++;
    await super.dispose();
  }
}
