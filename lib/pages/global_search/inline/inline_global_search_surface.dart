import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../global_search_logic.dart';
import '../global_search_view.dart';
import '../../chat/history_search/widgets/chat_history_search_bar.dart';
import 'inline_global_search_field.dart';
import 'inline_global_search_tokens.dart';

/// Expands the current list into global search without pushing another route.
class InlineGlobalSearchSurface extends StatefulWidget {
  const InlineGlobalSearchSurface({
    super.key,
    required this.feedBuilder,
    this.onSearchModeChanged,
    this.onWillOpen,
    this.createSearch,
    this.entryKey = const ValueKey('global-search-entry'),
    this.toolbarHeight = kToolbarHeight,
  });

  final Widget Function(Widget searchPlaceholder) feedBuilder;
  final bool Function()? onWillOpen;
  final ValueChanged<bool>? onSearchModeChanged;
  final GlobalSearchLogic Function()? createSearch;
  final Key entryKey;
  final double toolbarHeight;

  @override
  State<InlineGlobalSearchSurface> createState() => _SearchSurfaceState();
}

class _SearchSurfaceState extends State<InlineGlobalSearchSurface>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: InlineGlobalSearchTokens.transitionDuration,
  )..addStatusListener(_animationChanged);
  late final _transition = CurvedAnimation(
    parent: _animation,
    curve: InlineGlobalSearchTokens.transitionCurve,
  );
  GlobalSearchLogic? _search;
  LocalHistoryEntry? _history;
  bool _closing = false;
  bool _disposing = false;
  final _idleController = TextEditingController();
  final _idleFocus = FocusNode(canRequestFocus: false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animation.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : InlineGlobalSearchTokens.transitionDuration;
  }

  void _open() {
    if (_search != null || widget.onWillOpen?.call() == false) return;
    final search = widget.createSearch?.call() ?? GlobalSearchLogic();
    search.onStart();
    setState(() => _search = search);
    _history = LocalHistoryEntry(onRemove: () {
      _history = null;
      _close();
    });
    ModalRoute.of(context)?.addLocalHistoryEntry(_history!);
    widget.onSearchModeChanged?.call(true);
    _animation.forward();
  }

  void _cancel() {
    final history = _history;
    if (history != null) {
      history.remove();
    } else {
      _close();
    }
  }

  void _close() {
    if (_disposing || _search == null || _closing) return;
    _search!.focusNode.unfocus();
    // The input stays mounted while returning to the feed. An IME can still
    // be visible after focus was lost, so dismiss it explicitly on every exit.
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() => _closing = true);
    _animation.reverse();
    // Cancel can arrive before the first animation frame.
    if (_animation.isDismissed) _finishClose();
  }

  void _animationChanged(AnimationStatus status) {
    if (_disposing) return;
    if (status == AnimationStatus.completed) {
      final search = _search;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_closing &&
            identical(_search, search) &&
            ModalRoute.of(context)?.isCurrent != false) {
          search?.focusNode.requestFocus();
        }
      });
    } else if (status == AnimationStatus.dismissed && _closing) {
      _finishClose();
    }
  }

  void _finishClose() {
    final search = _search;
    if (search == null) return;
    setState(() {
      _search = null;
      _closing = false;
    });
    widget.onSearchModeChanged?.call(false);
    // Rebind the mounted input before releasing the search session's resources.
    WidgetsBinding.instance.addPostFrameCallback((_) => search.onDelete());
  }

  @override
  void dispose() {
    _disposing = true;
    _history?.remove();
    _transition.dispose();
    _animation.dispose();
    _search?.onDelete();
    _idleController.dispose();
    _idleFocus.dispose();
    if (_search != null) {
      final publish = widget.onSearchModeChanged;
      WidgetsBinding.instance.addPostFrameCallback((_) => publish?.call(false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barHeight = ChatHistorySearchBar.height(context);
    final feed = widget.feedBuilder(SizedBox(height: barHeight));
    final search = _search;
    return PopScope(
      canPop: search == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _search != null) _cancel();
      },
      child: AnimatedBuilder(
        animation: _transition,
        child: feed,
        builder: (context, feed) {
          final progress = _transition.value;
          return ClipRect(
            child: Stack(fit: StackFit.expand, children: [
              Offstage(
                offstage: progress == 1,
                child: IgnorePointer(
                  ignoring: search != null,
                  child: ExcludeSemantics(
                    excluding: search != null,
                    child: Transform.translate(
                      offset: Offset(0, -widget.toolbarHeight * progress),
                      child: Opacity(opacity: 1 - progress, child: feed),
                    ),
                  ),
                ),
              ),
              if (search != null)
                IgnorePointer(
                  ignoring: _closing,
                  child: Transform.translate(
                    offset: Offset(0, widget.toolbarHeight * (1 - progress)),
                    child: Opacity(
                      opacity: progress,
                      child: GlobalSearchPage(
                        key: ObjectKey(search),
                        logic: search,
                        autofocus: false,
                        onCancel: _cancel,
                        searchBar: SizedBox(height: barHeight),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: MediaQuery.paddingOf(context).top +
                    widget.toolbarHeight * (1 - progress),
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: _closing,
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InlineGlobalSearchField(
                        fieldKey: widget.entryKey,
                        controller: search?.searchCtrl ?? _idleController,
                        focusNode: search?.focusNode ?? _idleFocus,
                        progress: progress,
                        searching: search != null && !_closing,
                        onOpen: _open,
                        onCancel: _cancel,
                        onSubmit: () => _search?.search(),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}
