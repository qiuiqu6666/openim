import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';

/// Checks actual scroll extent after layout, including short/filtered pages.
class MediaGridPagination extends StatefulWidget {
  const MediaGridPagination(
      {super.key,
      required this.load,
      required this.onLoaded,
      required this.builder});
  final Future<bool> Function()? load;
  final VoidCallback onLoaded;
  final Widget Function(ScrollController controller) builder;
  @override
  State<MediaGridPagination> createState() => _MediaGridPaginationState();
}

class _MediaGridPaginationState extends State<MediaGridPagination> {
  final _scroll = ScrollController();
  bool _loading = false, _more = true, _failed = false;
  bool _atEnd = false;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
  }

  void _check() {
    if (!mounted || !_scroll.hasClients) return;
    final atEnd = _scroll.position.extentAfter <= 1;
    if (_atEnd != atEnd) setState(() => _atEnd = atEnd);
    if (!mounted ||
        _loading ||
        !_more ||
        _failed ||
        widget.load == null ||
        !_scroll.hasClients) {
      return;
    }
    if (_scroll.position.extentAfter < 160) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final more = await widget.load!();
      if (!mounted) return;
      _more = more;
      widget.onLoaded();
    } catch (_) {
      if (mounted) _failed = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Column(children: [
      Expanded(child: widget.builder(_scroll)),
      if (_loading) const LinearProgressIndicator(),
      if (!_more && !_loading && !_failed)
        Visibility(
          visible: _atEnd,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(zh ? AppCopy.text('没有更多了') : 'No more items',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
        ),
      if (_failed)
        TextButton(
            onPressed: _load,
            child: Text(zh ? '加载失败，点击重试' : 'Loading failed. Retry')),
    ]);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}
