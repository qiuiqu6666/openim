import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/chat/chat_list_viewport.dart';

final created = <String, int>{};
final destroyed = <String, int>{};

class Probe extends StatefulWidget {
  const Probe(this.id, {super.key});
  final String id;
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  @override
  void initState() {
    super.initState();
    created.update(widget.id, (n) => n + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    destroyed.update(widget.id, (n) => n + 1, ifAbsent: () => 1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 48, child: Text(widget.id));
}

void main() {
  testWidgets('viewport preserves existing visible row state on arrival',
      (tester) async {
    final controller = ScrollController();
    var ids = List.generate(30, (i) => 'm$i');
    Widget view() => MaterialApp(
        home: Center(
            child: SizedBox(
                width: 360,
                height: 240,
                child: ChatListViewport(
                    messageIDs: ids,
                    itemCount: ids.length,
                    controller: controller,
                    padding: EdgeInsets.zero,
                    findChildIndexCallback: (key) =>
                        key is ValueKey<String> ? ids.indexOf(key.value) : null,
                    itemBuilder: (_, i) =>
                        Probe(ids[i], key: ValueKey(ids[i]))))));
    await tester.pumpWidget(view());
    await tester.pump();
    expect(created['m1'], 1);
    ids = ['new', ...ids];
    await tester.pumpWidget(view());
    await tester.pump();
    print(
        'UX_AUDIT existing visible m1: created=${created['m1']} destroyed=${destroyed['m1'] ?? 0} after one latest arrival');
    expect(created['m1'], 1);
    expect(destroyed['m1'] ?? 0, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
