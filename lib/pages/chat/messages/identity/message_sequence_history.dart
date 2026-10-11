/// Exact observed sequence ranges, not a highest-sequence watermark.
/// A hole is never treated as seen; normal contiguous traffic needs one range.
class MessageSequenceHistory {
  final _ranges = <(int, int)>[];
  final _unsequenced = <String>{};
  int get rangeCount => _ranges.length;
  int get unsequencedCount => _unsequenced.length;

  bool contains(String id, int? sequence) {
    if (_unsequenced.contains(id)) return true;
    if (sequence == null || sequence <= 0) return false;
    final index = _after(sequence);
    return index > 0 && _ranges[index - 1].$2 >= sequence;
  }

  bool add(String id, int? sequence) {
    final seen = contains(id, sequence);
    if (sequence == null || sequence <= 0) {
      _unsequenced.add(id);
      return !seen;
    }
    final index = _after(sequence);
    if (index > 0 && _ranges[index - 1].$2 >= sequence) return !seen;
    final left = index > 0 && _ranges[index - 1].$2 + 1 == sequence;
    final right = index < _ranges.length && _ranges[index].$1 == sequence + 1;
    if (left && right) {
      _ranges[index - 1] = (_ranges[index - 1].$1, _ranges[index].$2);
      _ranges.removeAt(index);
    } else if (left) {
      _ranges[index - 1] = (_ranges[index - 1].$1, sequence);
    } else if (right) {
      _ranges[index] = (sequence, _ranges[index].$2);
    } else {
      _ranges.insert(index, (sequence, sequence));
    }
    return !seen;
  }

  int _after(int value) {
    var low = 0, high = _ranges.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_ranges[middle].$1 <= value) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  void clear() {
    _ranges.clear();
    _unsequenced.clear();
  }
}
