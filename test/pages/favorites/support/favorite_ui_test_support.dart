import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim/services/favorite_repository.dart';

const uiQuota =
    FavoriteQuota(supportsFavorites: true, supportsPrepareSend: true);
const uiNote = FavoriteItem(
    id: 'note-1',
    kind: FavoriteKind.note,
    title: '工作笔记',
    version: 1,
    contentRevision: 'revision-1',
    status: FavoriteStatus.ready,
    content: FavoriteContent(
        kind: FavoriteKind.note,
        blocks: [FavoriteBlock(id: 'b1', type: 'text', text: '保留收藏正文')]));

class FavoriteUiRepository extends FavoriteRepository {
  FavoriteUiRepository(
      {FavoriteQuota? initialQuota = uiQuota,
      List<FavoriteItem> initial = const [uiNote]})
      : capabilities = initialQuota,
        values = List.of(initial),
        super(
            api: FavoriteApi(
                client: Dio(),
                baseUrl: 'https://favorites.test.invalid',
                tokenProvider: () => 'test-token'),
            userIDProvider: () => 'test-account',
            cacheEnabled: false);
  final List<FavoriteItem> values;
  FavoriteQuota? capabilities;
  bool active = true;
  bool busyCapabilities = false;
  String? capabilityFailure;
  Future<FavoriteQuota> Function(bool)? probe;
  final List<bool> probeForces = [];
  final List<({String query, FavoriteKind? kind, String? tagID})> queries = [];
  int detailCalls = 0;
  int saves = 0;
  int batchDeletes = 0;
  int singleDeletes = 0;
  int syncCalls = 0;
  FavoriteBatchDeleteResult? deleteResult;
  String _query = '';
  FavoriteKind? _kind;
  @override
  String get sessionScope => 'ui-test-scope';
  @override
  bool isSessionCurrent(String scope) => active && scope == 'ui-test-scope';
  @override
  bool get available => active && capabilities?.available == true;
  @override
  FavoriteQuota? get quota => capabilities;
  @override
  bool get capabilitiesLoading => busyCapabilities;
  @override
  String? get capabilityError => capabilityFailure;
  @override
  List<FavoriteItem> get items => List.unmodifiable(values);
  @override
  String get query => _query;
  @override
  FavoriteKind? get filterKind => _kind;
  @override
  bool get hasMore => false;
  @override
  List<FavoriteMutationEntry> get pendingRecovery => const [];
  bool get observing => hasListeners;
  @override
  Future<FavoriteQuota> ensureCapabilities({bool force = false}) async {
    if (!force && capabilities != null) return capabilities!;
    probeForces.add(force);
    busyCapabilities = true;
    capabilityFailure = null;
    notifyListeners();
    try {
      final result = await (probe?.call(force) ?? Future.value(uiQuota));
      capabilities = result;
      return result;
    } catch (error) {
      capabilities = null;
      capabilityFailure =
          error is FavoriteApiException ? error.message : '能力查询失败';
      rethrow;
    } finally {
      busyCapabilities = false;
      notifyListeners();
    }
  }

  @override
  Future<void> requireAvailable() async {
    final caps = await ensureCapabilities();
    if (!active || !caps.available) {
      throw const FavoriteApiException('FAVORITES_UNAVAILABLE', '收藏与快捷发送暂未开放');
    }
  }

  @override
  Future<void> refresh(
      {String? query, FavoriteKind? kind, String? tagID}) async {
    _query = query ?? _query;
    _kind = kind;
    queries.add((query: _query, kind: kind, tagID: tagID));
    notifyListeners();
  }

  @override
  Future<void> syncChanges() async {
    syncCalls++;
    syncError = null;
    replayError = null;
    notifyListeners();
  }

  @override
  Future<FavoriteItem> getDetail(String id) async {
    detailCalls++;
    return values.firstWhere((item) => item.id == id);
  }

  @override
  Future<FavoriteItem> createFromMessage(
      {required FavoriteSource source, String? clientRequestID}) async {
    saves++;
    return uiNote;
  }

  @override
  Future<void> delete(String id,
      {int? expectedVersion, String? clientRequestID}) async {
    singleDeletes++;
  }

  @override
  Future<FavoriteBatchDeleteResult> deleteMany(List<FavoriteItem> items,
      {String? clientRequestID}) async {
    batchDeletes++;
    final result = deleteResult ??
        FavoriteBatchDeleteResult(items: [
          for (final item in items)
            FavoriteDeleteResult(
                id: item.id, status: FavoriteDeleteStatus.deleted)
        ]);
    for (final item in result.items) {
      if (item.deleted) {
        values.removeWhere((value) => value.id == item.id);
      } else if (item.currentItem != null) {
        final at = values.indexWhere((value) => value.id == item.id);
        if (at >= 0) values[at] = item.currentItem!;
      }
    }
    notifyListeners();
    return result;
  }
}

Widget favoriteUiHost(Widget home, {bool dark = false, double textScale = 1}) =>
    ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate
            ],
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            builder: EasyLoading.init(
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(textScale),
                        disableAnimations: true),
                    child: child!)),
            home: home));
