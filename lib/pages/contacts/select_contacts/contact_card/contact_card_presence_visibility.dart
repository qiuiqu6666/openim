import 'package:flutter/widgets.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Reports removal as well as scrolling, so a filtered row stops presence work.
class ContactCardPresenceVisibility extends StatefulWidget {
  const ContactCardPresenceVisibility({
    super.key,
    required this.userID,
    required this.onVisibilityChanged,
    required this.child,
  });

  final String userID;
  final void Function(Object rowOwner, String userID, bool visible)
      onVisibilityChanged;
  final Widget child;

  @override
  State<ContactCardPresenceVisibility> createState() =>
      _ContactCardPresenceVisibilityState();
}

class _ContactCardPresenceVisibilityState
    extends State<ContactCardPresenceVisibility> {
  late final _detectorKey = ObjectKey(this);

  @override
  void dispose() {
    VisibilityDetectorController.instance.forget(_detectorKey);
    widget.onVisibilityChanged(this, widget.userID, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VisibilityDetector(
        // Index changes can briefly mount two rows for the same friend. Each
        // detector owns its report, so disposing the old row cannot hide the new.
        key: _detectorKey,
        onVisibilityChanged: (info) {
          if (mounted) {
            widget.onVisibilityChanged(
                this, widget.userID, info.visibleFraction > 0);
          }
        },
        child: widget.child,
      );
}
