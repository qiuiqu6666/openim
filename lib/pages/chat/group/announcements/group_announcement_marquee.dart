import 'package:flutter/material.dart';

/// Mounted only while the announcement is visible and needs to scroll.
class GroupAnnouncementMarquee extends StatefulWidget {
  const GroupAnnouncementMarquee({
    super.key,
    required this.text,
    required this.style,
    required this.textWidth,
    required this.height,
  });

  final String text;
  final TextStyle style;
  final double textWidth, height;

  @override
  State<GroupAnnouncementMarquee> createState() =>
      _GroupAnnouncementMarqueeState();
}

class _GroupAnnouncementMarqueeState extends State<GroupAnnouncementMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final _position = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(-.5, 0),
  ).animate(_controller);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 36),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distance = widget.textWidth + 48;
    return ClipRect(
      child: SizedBox(
        height: widget.height,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: distance * 2,
          maxWidth: distance * 2,
          child: SlideTransition(
            position: _position,
            // Half of this fixed two-copy strip is exactly one loop distance.
            // Only its paint offset changes, never the text layout.
            child: Stack(children: [
              for (var i = 0; i < 2; i++)
                Positioned(
                  left: distance * i,
                  width: widget.textWidth + 1,
                  child: Text(widget.text,
                      style: widget.style, maxLines: 1, softWrap: false),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
