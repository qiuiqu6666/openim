import 'dart:io';
import 'dart:typed_data';

import 'package:extended_image/extended_image.dart';
import 'package:path_provider/path_provider.dart';

/// Shares encoded files with the chat bubble's ExtendedNetworkImageProvider.
/// Full URLs remain distinct: a real thumbnail must never replace an original.
class SharedImageDiskCache {
  SharedImageDiskCache({Future<Directory> Function()? temporaryDirectory})
      : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Future<Directory> Function() _temporaryDirectory;
  static int _serial = 0;

  Future<File> _file(String url) async => File(
      '${(await _temporaryDirectory()).path}/$cacheImageFolderName/${keyToMd5(url)}');

  Future<Uint8List?> read(String url) async {
    final file = await _file(url);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  }

  Future<void> write(String url, Uint8List bytes,
      {required bool Function() isCurrent}) async {
    if (bytes.isEmpty || !isCurrent()) return;
    final file = await _file(url);
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.viewer-${_serial++}.part');
    try {
      await pending.writeAsBytes(bytes, flush: true);
      if (!isCurrent()) return;
      await pending.rename(file.path);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  }
}
