import 'dart:io';

/// Route-owned asynchronous path checks shared by full images and thumbnails.
class LocalMediaAvailability {
  final Map<String, Future<bool>> _checks = {};
  final Map<String, bool> _available = {};

  Future<bool> exists(File file) => _checks.putIfAbsent(file.path, () {
        late final Future<bool> check;
        check = _check(file).then((available) {
          if (identical(_checks[file.path], check)) {
            _available[file.path] = available;
          }
          return available;
        });
        return check;
      });

  Future<bool> _check(File file) async {
    try {
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// New sources may refer to files that finished downloading in this route.
  /// Keep known available files, but retry missing and still-pending checks.
  void invalidateMissing() {
    final missing =
        _checks.keys.where((path) => _available[path] != true).toList();
    for (final path in missing) {
      invalidate(path);
    }
  }

  void invalidate(String path) {
    _checks.remove(path);
    _available.remove(path);
  }

  void clear() {
    _checks.clear();
    _available.clear();
  }
}
