import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
              alignment: Alignment.bottomCenter,
              child: Padding(
                  padding: const EdgeInsets.only(
                      bottom: kBottomNavigationBarHeight +
                          kMinInteractiveDimension),
                  child: FilledButton.tonal(
                    onPressed: () => setState(() => _original = true),
                    child: Text('mediaViewOriginal'.tr),
                  )),
            ),
          ),
      ]);
}
