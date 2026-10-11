import 'dart:typed_data';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class ViewerTestCache extends Fake implements BaseCacheManager {
  @override
  Future<FileInfo?> getFileFromCache(String key,
          {bool ignoreMemCache = false}) async =>
      null;
  @override
  Future<Never> putFile(String url, Uint8List bytes,
          {String? key,
          String? eTag,
          Duration maxAge = const Duration(days: 30),
          String fileExtension = 'file'}) async =>
      throw UnimplementedError('No persistence in network ownership tests');
}
