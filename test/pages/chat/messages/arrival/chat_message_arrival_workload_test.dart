import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/arrival/chat_message_arrival_animations.dart';
import 'package:openim/pages/chat/messages/arrival/chat_message_arrival_controller.dart';
import 'package:openim_common/src/widgets/chat/chat_list_viewport.dart';

// Exercise the real animated rows and viewport without network/image decoding.
// The regression guard compares sustained layout work with direct insertion;
// one initial entrance is allowed, continuous frame-by-frame growth is not.
class Counts {
  int rowBuilds = 0, rowLayouts = 0, viewportReports = 0;
}

class RowProbe extends SingleChildRenderObjectWidget {
  const RowProbe(this.counts, {required super.child});
  final Counts counts;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderRowProbe(counts);
}

class RenderRowProbe extends RenderProxyBox {
  RenderRowProbe(this.counts);
  final Counts counts;
  @override
  void performLayout() {
    counts.rowLayouts++;
    super.performLayout();
  }
}

class MotionHost extends StatefulWidget {
  const MotionHost({super.key, required this.enabled, required this.counts});
  final bool enabled;
  final Counts counts;
  @override
  State<MotionHost> createState() => MotionHostState();
}

class MotionHostState extends State<MotionHost> with TickerProviderStateMixin {
  final arrivals = ChatMessageArrivalController(currentUserID: () => 'self');
  late final animations =
      ChatMessageArrivalAnimations(vsync: this, arrivals: arrivals);
  final controller = ScrollController();
  var ids = List.generate(600, (i) => 'history-$i');

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    arrivals.addListener(changed);
  }

  void receive(int n) {
    final id = 'new-$n';
    arrivals.register(
        Message(
            clientMsgID: id, sendID: 'peer', contentType: MessageType.picture),
        enabled: widget.enabled);
    setState(() => ids = [id, ...ids.take(599)]);
  }

  @override
  void dispose() {
    arrivals.removeListener(changed);
    animations.dispose();
    arrivals.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    animations.sync(ids.toSet(), enabled: widget.enabled);
    final indices = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    return ChatListViewport(
        messageIDs: ids,
        itemCount: ids.length,
        controller: controller,
        padding: EdgeInsets.zero,
        findChildIndexCallback: (key) =>
            key is ValueKey<String> ? indices[key.value] : null,
        onViewportChanged: (_, __) => widget.counts.viewportReports++,
        itemBuilder: (_, i) {
          widget.counts.rowBuilds++;
          return KeyedSubtree(
              key: ValueKey(ids[i]),
              child: RowProbe(widget.counts,
                  child: animations.wrap(ids[i], const SizedBox(height: 240))));
        });
  }
}

void main() {
  testWidgets('sustained arrivals stop producing layout on every frame',
      (tester) async {
    final results = <bool, Counts>{};
    for (final enabled in [false, true]) {
      final counts = Counts();
      results[enabled] = counts;
      final key = GlobalKey<MotionHostState>();
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: SizedBox(
                  width: 375,
                  height: 600,
                  child: MotionHost(
                      key: key, enabled: enabled, counts: counts)))));
      await tester.pumpAndSettle();
      counts.rowBuilds = counts.rowLayouts = counts.viewportReports = 0;
      var received = 0;
      for (var frame = 0; frame < 240; frame++) {
        if (frame % 12 == 0) key.currentState!.receive(received++);
        await tester.pump(const Duration(microseconds: 16667));
      }
      await tester.pumpAndSettle();
      expect(received, 20);
      expect(key.currentState!.ids.length, 600);
      expect(key.currentState!.arrivals.hasEntering, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
    }
    final direct = results[false]!;
    final animated = results[true]!;
    // This deliberately allows startup motion and incidental framework work.
    // Previously these ratios were 15.85 and 12.1 over the same four seconds.
    expect(animated.rowLayouts, lessThan(direct.rowLayouts * 4));
    expect(animated.viewportReports, lessThan(direct.viewportReports * 4));
  });
}
