import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'media_preview_action_button.dart';

/// Keeps preview and original requests separate, including failed upgrades.
class OnDemandImage extends StatefulWidget {
  const OnDemandImage(
      {super.key, required this.preview, required this.original});
  final WidgetBuilder preview, original;

  @override
  State<OnDemandImage> createState() => _OnDemandImageState();
}

class _OnDemandImageState extends State<OnDemandImage> {
  bool _original = false;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        _original ? widget.original(context) : widget.preview(context),
        if (!_original)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 72),
                  child: MediaPreviewActionButton(
                    onPressed: () => setState(() => _original = true),
                    label: 'mediaViewOriginal'.tr,
                  )),
            ),
          ),
      ]);
}
