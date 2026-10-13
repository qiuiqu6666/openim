import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/summary/conversation_row_indices.dart';

void main() {
  test(
      'payload updates reuse indices; reorder, filter and archive offset invalidate',
      () {
    final cache = ConversationRowIndices();
    final a = ConversationInfo(conversationID: 'a');
    final b = ConversationInfo(conversationID: 'b');
    final initial = cache.read([a, b], offset: 0);
    a.unreadCount = 4;
    expect(identical(cache.read([a, b], offset: 0), initial), isTrue);
    final reordered = cache.read([b, a], offset: 0);
    expect(reordered[const ValueKey('slide-scope-a')], 1);
    expect(initial[const ValueKey('slide-scope-a')], 0);
    final archived = cache.read([b, a], offset: 1);
    expect(archived[const ValueKey('slide-scope-a')], 2);
    expect(cache.read([a], offset: 0), {const ValueKey('slide-scope-a'): 0});
    expect(cache.read([], offset: 0), isEmpty);
  });
}
