import 'package:flutter/widgets.dart';

/// Popup routes leave the underlying video visible. Navigator disables ticker
/// mode once an opaque page covers this subtree; application backgrounding is
/// handled independently by the playback owner's lifecycle observer.
bool liveSurfaceIsVisible(BuildContext context) =>
    TickerMode.valuesOf(context).enabled && ModalRoute.of(context)?.isActive != false;
