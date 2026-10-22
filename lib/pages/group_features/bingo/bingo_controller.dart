import 'dart:async';
import 'package:flutter/widgets.dart';
import 'bingo_draw.dart';
import 'bingo_repository.dart';

class BingoController extends ChangeNotifier with WidgetsBindingObserver {
  BingoController({BingoRepository? repository, required this.current})
      : repository = repository ?? BingoRepository(),
        _useCache = repository == null {
    if (_useCache &&
        _cachedDraw != null &&
        _cacheAge.elapsed < const Duration(minutes: 5)) {
      draw = _cachedDraw;
      _serverOffset = _cacheAge.elapsed;
      _clock.start();
    }
  }
  // Public lottery data only; no user or group information is cached.
  static BingoDraw? _cachedDraw;
  static final Stopwatch _cacheAge = Stopwatch();
  final bool _useCache;
  Duration _serverOffset = Duration.zero;
  final BingoRepository repository;
  final bool Function() current;
  BingoDraw? draw;
  String? error;
  bool loading = false;
  bool _disposed = false;
  bool _foreground = true;
  int _users = 0, _generation = 0;
  Timer? _timer;
  Future<void>? _work;
  final Stopwatch _clock = Stopwatch();
  DateTime? get now => draw?.serverTime?.add(_serverOffset + _clock.elapsed);

  void attach() {
    if (_disposed || ++_users != 1) return;
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (_foreground) _start();
  }

  void _start() {
    _timer?.cancel();
    unawaited(refresh());
    var ticks = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!current()) {
        _stop();
        notifyListeners();
        return;
      }
      notifyListeners();
      if (++ticks % 15 == 0) unawaited(refresh());
    });
  }

  void _stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    repository.cancel();
    _work = null;
    loading = false;
  }

  void detach() {
    if (_users == 0 || --_users != 0) return;
    WidgetsBinding.instance.removeObserver(this);
    _stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _users > 0) {
      _start();
    } else {
      _stop();
    }
  }

  Future<void> refresh() {
    if (_disposed || !_foreground || !current()) return Future.value();
    if (_work != null) return _work!;
    final generation = _generation;
    loading = true;
    notifyListeners();
    late final Future<void> work;
    work = _fetch(generation).whenComplete(() {
      if (identical(_work, work)) _work = null;
    });
    _work = work;
    return work;
  }

  Future<void> _fetch(int generation) async {
    try {
      final next = await repository.fetch();
      if (!_valid(generation)) return;
      if (draw != null && next.drawTime.isBefore(draw!.drawTime)) {
        throw const FormatException('开奖数据尚未更新');
      }
      draw = next;
      _serverOffset = Duration.zero;
      if (_useCache) {
        _cachedDraw = next;
        _cacheAge
          ..reset()
          ..start();
      }
      error = null;
      _clock
        ..reset()
        ..start();
    } catch (_) {
      if (_valid(generation)) {
        error = draw == null ? '宾果开奖加载失败，点击重试' : '更新失败，当前显示上次结果';
      }
    } finally {
      if (_valid(generation)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  bool _valid(int generation) =>
      !_disposed && generation == _generation && current();

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    repository.dispose();
    super.dispose();
  }
}
