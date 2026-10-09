import 'dart:async';
import 'package:flutter/material.dart';
import '../data/group_feature_store.dart';
import '../models/group_feature_context.dart';
import '../live/group_live_module.dart';
import '../sangong/sangong_module.dart';
import '../mark_six/mark_six.dart';

/// The three independent feature scopes share one bounded chat surface.
/// No networking happens in build; stream/player ownership remains in each module.
class GroupChatFeatureSurface extends StatefulWidget {
  const GroupChatFeatureSurface(
      {super.key,
      required this.store,
      required this.featureContext,
      required this.child});
  final GroupFeatureStore store;
  final GroupFeatureContext featureContext;
  final Widget child;
  @override
  State<GroupChatFeatureSurface> createState() =>
      _GroupChatFeatureSurfaceState();
}

class _GroupChatFeatureSurfaceState extends State<GroupChatFeatureSurface> {
  StreamSubscription<Map<String, dynamic>>? _events;
  int _bindingGeneration = 0;
  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    final generation = ++_bindingGeneration;
    final feature = widget.featureContext;
    final store = widget.store;
    bool current() =>
        mounted && generation == _bindingGeneration && feature.sessionCurrent();
    _events = feature.events.listen((event) {
      if (event['key'] == 'groupFeatureCapabilitiesChanged' && current()) {
        unawaited(store.loadCapabilities(feature.groupID));
      }
    });
    scheduleMicrotask(() {
      if (current()) {
        // Re-entering a group must discover account settings changed while the
        // app stayed in the foreground. The account store fences old sessions.
        unawaited(feature.privilege.refresh());
        unawaited(store.loadCapabilities(feature.groupID, force: true));
      }
    });
  }

  @override
  void didUpdateWidget(GroupChatFeatureSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.featureContext.groupID != widget.featureContext.groupID ||
        oldWidget.store != widget.store ||
        !identical(oldWidget.featureContext.privilege,
            widget.featureContext.privilege) ||
        oldWidget.featureContext.currentUserID !=
            widget.featureContext.currentUserID ||
        !identical(oldWidget.featureContext.api, widget.featureContext.api)) {
      _events?.cancel();
      _attach();
    }
  }

  @override
  void dispose() {
    _bindingGeneration++;
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feature = widget.featureContext;
    if (!feature.sessionCurrent()) return widget.child;
    return SangongFeatureHost(
        featureContext: feature,
        builder: (context, status, sangongOverlay) => MarkSixFeatureHost(
            featureContext: feature,
            builder: (context, entry, markSixOverlay) => Stack(children: [
                  Positioned.fill(
                      child: Column(children: [
                    GroupLiveFeatureHost(featureContext: feature),
                    status,
                    entry,
                    Expanded(child: widget.child),
                  ])),
                  sangongOverlay,
                  markSixOverlay,
                ])));
  }
}
