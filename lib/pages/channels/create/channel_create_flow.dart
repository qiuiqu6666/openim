import 'package:flutter/material.dart';
import 'channel_contact_picker.dart';
import '../models/channel_preview.dart';

/// A single modal contains the picker and form, preserving selections on Back.
class ChannelCreateFlow extends StatefulWidget {
  const ChannelCreateFlow({super.key, this.onSubmit});
  final Future<void> Function(ChannelPreview)? onSubmit;
  @override
  State<ChannelCreateFlow> createState() => _ChannelCreateFlowState();
}

class _ChannelCreateFlowState extends State<ChannelCreateFlow> {
  final _navigator = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
      onPopWithResult: (_) => _navigator.currentState!.maybePop(),
      child: Navigator(
          key: _navigator,
          onGenerateRoute: (_) => MaterialPageRoute(
              builder: (_) => ChannelContactPicker(
                    onSubmit: widget.onSubmit,
                    onClose: () => Navigator.of(context).pop(),
                    onCompleted: (channel) =>
                        Navigator.of(context).pop(channel),
                  ))));
}
