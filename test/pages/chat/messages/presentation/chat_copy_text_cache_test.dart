import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/messages/presentation/chat_copy_text_cache.dart';

class _IM extends GetxController implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.put<IMController>(_IM()));
  tearDown(Get.reset);

  test('long chat sessions bound rendered copy text and retain recent text',
      () {
    final cache = ChatLogic().copyTextMap;
    for (var index = 0; index < 10000; index++) {
      cache['message-$index'] = 'Rendered mention @Alice $index';
    }
    expect(cache.length, lessThanOrEqualTo(600));
    expect(cache['message-9999'], 'Rendered mention @Alice 9999');
    expect(cache.containsKey('message-0'), isFalse);
  });

  test('recently copied or rendered rows survive eviction and can be removed',
      () {
    final cache = ChatCopyTextCache(maxEntries: 2);
    cache['alice'] = '@Alice';
    cache['bob'] = '@Bob';
    expect(cache['alice'], '@Alice');
    cache['carol'] = '@Carol';
    expect(cache.containsKey('bob'), isFalse);
    cache['alice'] = '@Alice updated';
    cache['dave'] = '@Dave';
    expect(cache['alice'], '@Alice updated');
    expect(cache.remove('alice'), '@Alice updated');
    expect(cache.containsKey('alice'), isFalse);
    cache.clear();
    expect(cache, isEmpty);
  });
}
