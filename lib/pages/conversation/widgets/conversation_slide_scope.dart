import 'package:flutter/widgets.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

/// A controller belongs to one mounted row, never to a cached conversation ID.
/// This also prevents old flutter_slidable notification listeners from being
/// reused when a filtered/list-index-shifted row is mounted again.
class ConversationSlideScope extends StatefulWidget {
  const ConversationSlideScope({
    super.key,
    required this.onCreated,
    required this.onDisposed,
    required this.builder,
  });

  final ValueChanged<SlidableController> onCreated;
  final ValueChanged<SlidableController> onDisposed;
  final Widget Function(BuildContext, SlidableController) builder;

  @override
  State<ConversationSlideScope> createState() => _ConversationSlideScopeState();
}

class _ConversationSlideScopeState extends State<ConversationSlideScope>
    with SingleTickerProviderStateMixin {
  late final _controller = SlidableController(this);

  @override
  void initState() {
    super.initState();
    widget.onCreated(_controller);
  }

  @override
  void dispose() {
    widget.onDisposed(_controller);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
