import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim/services/moments_repository.dart';

const renderTestUser = MomentUser(userId: 'me');

Uint8List renderTestPng() => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a/q8AAAAASUVORK5CYII=');

Widget renderTestHost(Widget child,
        {Brightness brightness = Brightness.light}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        locale: const Locale('en'),
        theme: ThemeData(brightness: brightness),
        home: Scaffold(body: child),
      ),
    );

class RenderTestApi extends MomentsApi {
  int feedPage = 0;
  Future<MomentsPageResult<MomentPost>> Function(String?)? feedWork;
  Future<MomentsPageResult<MomentPost>> Function(String)? albumWork;
  Future<Uint8List> Function(MomentMedia, bool)? mediaWork;
  final mediaCalls = <String>[];

  @override
  Future<MomentsCapabilities> capabilities() async =>
      const MomentsCapabilities(enabled: true, readEnabled: true);

  @override
  Future<MomentsPageResult<MomentPost>> feed(
      {String? cursor, int pageSize = 20}) async {
    if (feedWork != null) return feedWork!(cursor);
    final page = feedPage++;
    return MomentsPageResult(
      items: List.generate(20,
          (i) => MomentPost(momentId: 'page-$page-$i', author: renderTestUser)),
      nextCursor: '$feedPage',
      hasMore: true,
    );
  }

  @override
  Future<MomentsPageResult<MomentPost>> userMoments(String userId,
          {String? cursor, int pageSize = 20}) async =>
      albumWork?.call(userId) ?? const MomentsPageResult(items: []);

  @override
  Future<void> deletePost(String momentId) async {}

  @override
  Future<Uint8List> downloadMedia(MomentMedia media,
      {bool thumbnail = false}) async {
    mediaCalls.add('${media.mediaId}:$thumbnail');
    return mediaWork?.call(media, thumbnail) ?? renderTestPng();
  }
}

MomentsRepository renderTestRepository(RenderTestApi api) => MomentsRepository(
      api: api,
      userIdProvider: () => 'me',
      environmentProvider: () => 'render-test',
      friendLoader: () async => const [],
      subscribeToSdk: false,
    );
