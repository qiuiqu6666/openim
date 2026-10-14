import 'dart:collection';

/// Rendered mentions/quotes can be recomputed when a row is mounted again.
/// Keep the most recently rendered/copied text, not the entire chat session.
class ChatCopyTextCache extends MapBase<String?, String?> {
  ChatCopyTextCache({this.maxEntries = 600}) : assert(maxEntries > 0);

  final int maxEntries;
  final _values = <String?, String?>{};

  @override
  String? operator [](Object? key) {
    if (!_values.containsKey(key)) return null;
    final value = _values.remove(key);
    _values[key as String?] = value;
    return value;
  }

  @override
  void operator []=(String? key, String? value) {
    _values.remove(key);
    _values[key] = value;
    if (_values.length > maxEntries) _values.remove(_values.keys.first);
  }

  @override
  bool containsKey(Object? key) => _values.containsKey(key);

  @override
  Iterable<String?> get keys => List<String?>.of(_values.keys, growable: false);

  @override
  int get length => _values.length;

  @override
  String? remove(Object? key) => _values.remove(key);

  @override
  void clear() => _values.clear();
}
