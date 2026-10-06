import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_list_viewport.dart';

export 'scrolling/chat_list_position_controller.dart'
    show ChatListPositionController;

extension ScrollControllerExt on ScrollController {
  Future scrollToBottom(Function()? onScrollStop) async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      while (position.pixels != position.maxScrollExtent) {
        jumpTo(position.maxScrollExtent);
        await SchedulerBinding.instance.endOfFrame;
      }
      onScrollStop?.call();
    });
  }

  Future scrollToTop() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      while (position.pixels != position.minScrollExtent) {
        jumpTo(position.minScrollExtent);
        await SchedulerBinding.instance.endOfFrame;
      }
    });
  }
}

class CustomChatListViewController<E> extends ChangeNotifier {
  final _topList = <E>[];

  final _bottomList = <E>[];

  List<E> get topList => _topList;

  List<E> get bottomList => _bottomList;

  List<E> get list => _topList + _bottomList;

  int get length => list.length;

  bool topHasMore = true;
  bool bottomHasMore = true;

  CustomChatListViewController(List<E> list) {
    _bottomList.addAll(list);
  }

  void insertToTop(E data) {
    _topList.insert(0, data);
  }

  void insertAllToTop(Iterable<E> iterable) {
    _topList.insertAll(0, iterable);
  }

  void insertToBottom(E data) {
    _bottomList.add(data);
  }

  void insertAllToBottom(Iterable<E> iterable) {
    _bottomList.addAll(iterable);
  }

  void bottomLoadCompleted(bool hasMore) {
    bottomHasMore = hasMore;
    notifyListeners();
  }

  void topLoadCompleted(bool hasMore) {
    topHasMore = hasMore;
    notifyListeners();
  }

  E elementAt(int position) => list.elementAt(position);

  E removeAt(int position) => list.removeAt(position);

  bool remove(Object? value) => list.remove(value);
}

typedef CustomChatListViewItemBuilder<T> = Widget Function(
  BuildContext context,
  int index,
  int position,
  T data,
);

class CustomChatListView extends StatefulWidget {
  const CustomChatListView({
    Key? key,
    required this.itemBuilder,
    required this.controller,
    this.scrollController,
    this.onScrollToTopLoad,
    this.onScrollToBottomLoad,
    this.enabledBottomLoad = false,
    this.enabledTopLoad = false,
    this.indicatorColor,
  }) : super(key: key);

  final CustomChatListViewItemBuilder itemBuilder;

  final CustomChatListViewController controller;

  final ScrollController? scrollController;

  final Future<bool> Function()? onScrollToTopLoad;

  final Future<bool> Function()? onScrollToBottomLoad;

  final bool enabledTopLoad;

  final bool enabledBottomLoad;

  final Color? indicatorColor;

  @override
  State<CustomChatListView> createState() => _CustomChatListViewState();
}

class _CustomChatListViewState extends State<CustomChatListView> {
  final Key centerKey = const ValueKey('second-sliver-list');

  bool _bottomHasMore = true;

  bool _topHasMore = true;

  bool get _isBottom =>
      widget.scrollController!.offset ==
      widget.scrollController!.position.maxScrollExtent;

  bool get _isTop =>
      widget.scrollController!.offset ==
      widget.scrollController!.position.minScrollExtent;

  @override
  void initState() {
    widget.controller.addListener(_loadFinished);
    widget.scrollController?.addListener(_scrollListener);
    super.initState();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_loadFinished);
    widget.scrollController?.removeListener(_scrollListener);
    super.dispose();
  }

  void _loadFinished() {
    setState(() {
      _topHasMore = widget.controller.topHasMore;
      _bottomHasMore = widget.controller.bottomHasMore;
    });
  }

  void _scrollListener() {
    if (widget.enabledBottomLoad && _isBottom && _bottomHasMore) {
      _onScrollToBottomLoadMore();
    } else if (widget.enabledTopLoad && _isTop && _topHasMore) {
      _onScrollToTopLoadMore();
    }
  }

  void _onScrollToBottomLoadMore() {
    widget.onScrollToBottomLoad?.call().then((hasMore) {
      if (!mounted) return;
      setState(() {
        _bottomHasMore = hasMore;
      });
    });
  }

  void _onScrollToTopLoadMore() {
    widget.onScrollToTopLoad?.call().then((hasMore) {
      if (!mounted) return;
      setState(() {
        _topHasMore = hasMore;
      });
    });
  }

  Widget _buildLoadMoreView() => Container(
        alignment: Alignment.center,
        height: 44,
        child: CupertinoActivityIndicator(
          color: widget.indicatorColor ?? Colors.blueAccent,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      center: centerKey,
      controller: widget.scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        if (_topHasMore && widget.enabledTopLoad)
          SliverToBoxAdapter(child: _buildLoadMoreView()),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, index) {
              return widget.itemBuilder(
                context,
                index,
                widget.controller.topList.length - index - 1,
                widget.controller.topList
                    .elementAt(widget.controller.topList.length - 1 - index),
              );
            },
            childCount: widget.controller.topList.length,
          ),
        ),
        SliverList(
          key: centerKey,
          delegate: SliverChildBuilderDelegate(
            (_, index) {
              return widget.itemBuilder(
                context,
                index,
                widget.controller.topList.length + index,
                widget.controller.bottomList.elementAt(index),
              );
            },
            childCount: widget.controller.bottomList.length,
          ),
        ),
        if (_bottomHasMore && widget.enabledBottomLoad)
          SliverToBoxAdapter(child: _buildLoadMoreView()),
      ],
    );
  }
}

class ChatListView extends StatefulWidget {
  const ChatListView({
    Key? key,
    this.physics,
    this.onTouch,
    this.itemCount,
    this.controller,
    required this.itemBuilder,
    this.enabledScrollTopLoad = false,
    this.onScrollToBottomLoad,
    this.onScrollToTopLoad,
    this.onScrollToBottom,
    this.onScrollToTop,
    this.initialLoading = false,
    this.historyLoading = false,
    this.historyError,
    this.onRetry,
    this.hasMore,
    this.newerHasMore,
    this.pagingWindow,
    this.loadOnInit = true,
    this.findChildIndexCallback,
    this.messageIDs,
    this.onViewportChanged,
    this.positionController,
    this.emptyView,
  }) : super(key: key);
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final int? itemCount;
  final IndexedWidgetBuilder itemBuilder;

  final Future<bool> Function()? onScrollToBottomLoad;

  final Future<bool> Function()? onScrollToTopLoad;
  final Function()? onScrollToBottom;
  final Function()? onScrollToTop;

  final bool enabledScrollTopLoad;
  final Function()? onTouch;
  final bool initialLoading;
  final bool historyLoading;
  final String? historyError;
  final VoidCallback? onRetry;
  final bool? hasMore;
  // A route-owned history window can supersede an in-flight paging request.
  // Its newer boundary must not be overwritten by that old request's result.
  final bool? newerHasMore;
  // Changes only when the route installs or requests a different SDK window,
  // rather than when another page or live message extends the current list.
  final Object? pagingWindow;
  final bool loadOnInit;
  final int? Function(Key)? findChildIndexCallback;
  final List<String>? messageIDs;
  final ChatViewportChanged? onViewportChanged;
  final ChatListPositionController? positionController;
  final Widget? emptyView;

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  bool _scrollToBottomLoadMore = true;
  bool _scrollToTopLoadMore = true;
  bool _loadingBottom = false;
  bool _loadingTop = false;
  bool _bottomFailed = false;
  bool _topFailed = false;
  bool _emptyViewportScheduled = false;
  int _pagingGeneration = 0;

  static const _historyStatusKey = ValueKey('chat-history-status');
  bool get _hasMore => widget.hasMore ?? _scrollToBottomLoadMore;
  bool get _hasNewer => widget.newerHasMore ?? _scrollToTopLoadMore;
  bool get _hasHistoryError => _bottomFailed || widget.historyError != null;
  bool get _historyLoading => _loadingBottom || widget.historyLoading;
  bool get _pagingBusy =>
      _loadingBottom ||
      _loadingTop ||
      widget.historyLoading ||
      widget.initialLoading;

  bool get _isBottom =>
      widget.controller!.offset >= widget.controller!.position.maxScrollExtent;

  bool get _isTop =>
      widget.controller!.offset <=
      widget.controller!.position.minScrollExtent + 1;

  @override
  void dispose() {
    widget.controller?.removeListener(_scrollListener);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) _onScrollToBottomLoadMore();
    widget.controller?.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (widget.controller?.hasClients != true) return;
    if (_isBottom) {
      _onScrollToBottomLoadMore();
    } else if (_isTop) {
      _onScrollToTopLoadMore();
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth == 0 &&
        notification is OverscrollNotification &&
        notification.dragDetails != null) {
      // A short window has identical min/max extents, so the user's drag
      // direction is the only reliable way to choose which page to request.
      if (notification.overscroll > 0) {
        _onScrollToBottomLoadMore();
      } else if (notification.overscroll < 0) {
        _onScrollToTopLoadMore();
      }
    }
    return false;
  }

  Future<void> _onScrollToBottomLoadMore({bool retry = false}) async {
    widget.onScrollToBottom?.call();
    final load = widget.onScrollToBottomLoad;
    if (load == null ||
        _pagingBusy ||
        !retry && (!_hasMore || _hasHistoryError)) {
      return;
    }
    final generation = _pagingGeneration;
    setState(() {
      _loadingBottom = true;
      _bottomFailed = false;
    });
    try {
      final hasMore = await load();
      if (!mounted || generation != _pagingGeneration) return;
      setState(() {
        _scrollToBottomLoadMore = hasMore;
      });
    } catch (_) {
      if (mounted && generation == _pagingGeneration) {
        setState(() => _bottomFailed = true);
      }
    } finally {
      if (mounted && generation == _pagingGeneration) {
        setState(() => _loadingBottom = false);
      }
    }
  }

  Future<void> _onScrollToTopLoadMore({bool retry = false}) async {
    widget.onScrollToTop?.call();
    final load = widget.onScrollToTopLoad;
    if (!widget.enabledScrollTopLoad ||
        load == null ||
        _pagingBusy ||
        !retry && (!_hasNewer || _topFailed || widget.historyError != null)) {
      return;
    }
    final generation = _pagingGeneration;
    setState(() {
      _loadingTop = true;
      _topFailed = false;
    });
    try {
      final hasMore = await load();
      if (mounted &&
          generation == _pagingGeneration &&
          widget.newerHasMore == null) {
        setState(() => _scrollToTopLoadMore = hasMore);
      }
    } catch (_) {
      if (mounted && generation == _pagingGeneration) {
        setState(() => _topFailed = true);
      }
    } finally {
      if (mounted && generation == _pagingGeneration) {
        setState(() => _loadingTop = false);
      }
    }
  }

  @override
  void didUpdateWidget(covariant ChatListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pagingWindow != widget.pagingWindow) {
      // A seek supersedes old SDK requests. Their eventual completions must
      // neither hold this window busy nor release its new paging owner.
      _pagingGeneration++;
      _loadingBottom = false;
      _loadingTop = false;
      _bottomFailed = false;
      _topFailed = false;
      _scrollToBottomLoadMore = true;
      _scrollToTopLoadMore = true;
    }
    if (!oldWidget.enabledScrollTopLoad && widget.enabledScrollTopLoad) {
      // A fresh date window has its own newer edge. A previous window may have
      // exhausted that edge or failed while paging toward latest messages.
      _scrollToTopLoadMore = true;
      _topFailed = false;
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_scrollListener);
      widget.controller?.addListener(_scrollListener);
    }
  }

  void _retryHistory() {
    if (_pagingBusy) return;
    if (widget.onRetry != null) {
      setState(() => _bottomFailed = false);
      widget.onRetry!();
    } else {
      _onScrollToBottomLoadMore(retry: true);
    }
  }

  Widget _failure(VoidCallback retry) => Center(
        child: TextButton(
          onPressed: retry,
          child: Text('${'chatHistoryLoadFailed'.tr}\n${'chatHistoryRetry'.tr}',
              textAlign: TextAlign.center),
        ),
      );

  Widget _initialState() {
    if (widget.initialLoading || _historyLoading) {
      return Center(
        child: Semantics(
          label: 'chatHistoryLoading'.tr,
          child: CupertinoActivityIndicator(color: Styles.c_0089FF),
        ),
      );
    }
    if (_hasHistoryError) return _failure(_retryHistory);
    if (widget.emptyView != null) return widget.emptyView!;
    return Center(
        child: Text('chatHistoryEmpty'.tr, style: Styles.ts_8E9AB0_14sp));
  }

  Widget get loadMoreView => Container(
        alignment: Alignment.center,
        height: 44,
        child: CupertinoActivityIndicator(color: Styles.c_0089FF),
      );

  @override
  Widget build(BuildContext context) {
    if ((widget.itemCount ?? 0) == 0 &&
        !_emptyViewportScheduled &&
        widget.onViewportChanged != null) {
      _emptyViewportScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _emptyViewportScheduled = false;
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        if (mounted &&
            (widget.itemCount ?? 0) == 0 &&
            ModalRoute.of(context)?.isCurrent != false &&
            (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
          widget.onViewportChanged?.call(const [], 0);
        }
      });
    }
    final physics = widget.physics?.allowUserScrolling == false
        ? widget.physics!
        : AlwaysScrollableScrollPhysics(
            parent: widget.physics ?? const ClampingScrollPhysics());
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: TouchCloseSoftKeyboard(
        onTouch: widget.onTouch,
        child: (widget.itemCount ?? 0) == 0
            ? _initialState()
            : widget.messageIDs != null
                ? ChatListViewport(
                    messageIDs: widget.messageIDs!,
                    onViewportChanged: widget.onViewportChanged,
                    positionController: widget.positionController,
                    controller: widget.controller,
                    physics: physics,
                    itemCount: widget.itemCount! +
                        (_historyLoading || _hasHistoryError ? 1 : 0),
                    padding: EdgeInsets.only(top: 10.h),
                    findChildIndexCallback: (key) => key == _historyStatusKey
                        ? widget.itemCount
                        : widget.findChildIndexCallback?.call(key),
                    itemBuilder: (context, index) => _wrapLoadMoreItem(index),
                  )
                : Align(
                    alignment: Alignment.topCenter,
                    child: ListView.builder(
                      reverse: true,
                      shrinkWrap: true,
                      physics: physics,
                      itemCount: widget.itemCount! +
                          (_historyLoading || _hasHistoryError ? 1 : 0),
                      padding: EdgeInsets.only(top: 10.h),
                      controller: widget.controller,
                      findChildIndexCallback: (key) => key == _historyStatusKey
                          ? widget.itemCount
                          : widget.findChildIndexCallback?.call(key),
                      itemBuilder: (context, index) => _wrapLoadMoreItem(index),
                    ),
                  ),
      ),
    );
  }

  Widget _wrapLoadMoreItem(int index) {
    if (index == widget.itemCount) {
      return KeyedSubtree(
        key: _historyStatusKey,
        child: _historyLoading ? loadMoreView : _failure(_retryHistory),
      );
    }
    final child = widget.itemBuilder(context, index);
    if (index == 0 && widget.enabledScrollTopLoad) {
      return KeyedSubtree(
        key: child.key,
        child: Column(children: [
          child,
          if (_loadingTop) loadMoreView,
          if (_topFailed) _failure(() => _onScrollToTopLoadMore(retry: true)),
        ]),
      );
    }
    return child;
  }
}

class PositionRetainedScrollPhysics extends ClampingScrollPhysics {
  final bool shouldRetain;

  const PositionRetainedScrollPhysics({super.parent, this.shouldRetain = true});

  @override
  PositionRetainedScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return PositionRetainedScrollPhysics(
      parent: buildParent(ancestor),
      shouldRetain: shouldRetain,
    );
  }

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final position = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );

    final diff = newPosition.maxScrollExtent - oldPosition.maxScrollExtent;

    if (oldPosition.pixels > oldPosition.minScrollExtent &&
        diff > 0 &&
        shouldRetain) {
      return position + diff;
    } else {
      return position;
    }
  }
}
