import 'package:flutter/material.dart';
import '../models/group_features.dart';
import '../data/group_feature_store.dart';
import '../live/widgets/live_list_scope.dart';

/// Original 99chat badge dimensions; this view never initiates a request.
class GroupLiveAvatar extends StatelessWidget {
  const GroupLiveAvatar(
      {super.key,
      required this.child,
      this.store,
      this.groupID,
      this.features});
  final Widget child;
  final GroupFeatureStore? store;
  final String? groupID;
  final GroupFeatures? features;
  @override
  Widget build(BuildContext context) {
    if (store == null) {
      return _build(features?.live ?? const GroupLiveFeature());
    }
    final avatar = ListenableBuilder(
        listenable: store!,
        builder: (_, __) => _build(store!.liveFeature(groupID ?? '')));
    if (groupID == null || groupID!.isEmpty) return avatar;
    return GroupLiveListItem(groupID: groupID!, child: avatar);
  }

  Widget _build(GroupLiveFeature live) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            child,
            if (live.isActive)
              Positioned(
                  bottom: 0,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: switch (live.status) {
                            'live' => const Color(0xFFFF4B4B),
                            'ready' => const Color(0xFFFF6B35),
                            _ => const Color(0xFF1677FF)
                          },
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x26000000),
                                blurRadius: 3,
                                offset: Offset(0, 1))
                          ]),
                      child: Text(live.label,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                              height: 1.1)))),
          ]);
}
