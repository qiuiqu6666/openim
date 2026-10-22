import 'package:flutter/material.dart';
import 'bingo_draw.dart';
import 'bingo_repository.dart';
import 'bingo_history_table.dart';
import 'bingo_opened_statistics.dart';

class BingoHistoryPanel extends StatefulWidget {
  const BingoHistoryPanel(
      {super.key,
      required this.current,
      this.repository,
      this.statistics = false});
  final bool statistics;
  final bool Function() current;
  final BingoRepository? repository;
  @override
  State<BingoHistoryPanel> createState() => BingoHistoryPanelState();
}

class BingoHistoryPanelState extends State<BingoHistoryPanel>
    with WidgetsBindingObserver {
  late final _repository = widget.repository ?? BingoRepository();
  List<BingoDraw> _draws = [];
  bool _loading = false, _more = true;
  int _page = 0, _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  Future<void> refresh() => _load(reset: true);

  Future<void> _load({bool reset = false}) async {
    if (_loading || !widget.current()) return;
    final generation = ++_generation;
    final page = reset ? 0 : _page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.fetchHistory(page);
      if (!mounted || generation != _generation || !widget.current()) return;
      final unique = <String, BingoDraw>{
        if (!reset)
          for (final d in _draws) d.issue: d,
        for (final d in result.draws) d.issue: d,
      };
      setState(() {
        _draws = unique.values.toList()
          ..sort((a, b) => b.drawTime.compareTo(a.drawTime));
        _page = page + 1;
        _more = result.hasMore;
      });
    } catch (_) {
      if (mounted && generation == _generation && widget.current()) {
        setState(() => _error = '开奖记录加载失败，请重试');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _generation++;
      _repository.cancel();
      setState(() => _loading = false);
    } else if (_draws.isEmpty) {
      refresh();
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (_draws.isNotEmpty)
          widget.statistics
              ? BingoOpenedStatistics(draws: _draws)
              : BingoHistoryTable(draws: _draws),
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
        if (_error != null)
          TextButton(
              onPressed: () => _load(reset: _draws.isEmpty),
              child: Text(_error!)),
        if (!_loading && _error == null && _draws.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('暂无开奖记录')),
        if (!widget.statistics &&
            !_loading &&
            _error == null &&
            _draws.isNotEmpty)
          _more
              ? TextButton(onPressed: _load, child: const Text('加载更多'))
              : const Padding(
                  padding: EdgeInsets.all(12), child: Text('已显示全部记录')),
      ]);
}
