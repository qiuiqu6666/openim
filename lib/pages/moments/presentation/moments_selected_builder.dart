import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Rebuild only when the values used by this part of Moments change.
class MomentsSelectedBuilder extends StatefulWidget {
  const MomentsSelectedBuilder(
      {super.key,
      required this.listenable,
      required this.select,
      required this.builder});
  final Listenable listenable;
  final List<Object?> Function() select;
  final WidgetBuilder builder;
  @override
  State<MomentsSelectedBuilder> createState() => _MomentsSelectedBuilderState();
}

class _MomentsSelectedBuilderState extends State<MomentsSelectedBuilder> {
  late List<Object?> _values;
  @override
  void initState() {
    super.initState();
    _values = widget.select();
    widget.listenable.addListener(_changed);
  }

  void _changed() {
    final next = widget.select();
    if (!listEquals(_values, next)) setState(() => _values = next);
  }

  @override
  void didUpdateWidget(MomentsSelectedBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
    _values = widget.select();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
