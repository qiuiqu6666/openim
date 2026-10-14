import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/editing/batch_read/conversation_batch_read_api.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio previous;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'imToken': 'self-token',
      'chatToken': 'chat-token'
    }));
    previous = http.dio;
    http.dio = Dio();
  });
  tearDown(() {
    http.dio.close(force: true);
    http.dio = previous;
  });

  test('uses IM token, no caller-supplied user and validates result watermark',
      () async {
    http.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.headers['token'], 'self-token');
      expect((options.data as Map).containsKey('userID'), false);
      handler.resolve(Response(requestOptions: options, data: {
        'errCode': 0,
        'data': {
          'results': [
            {'conversationID': 'sg_a', 'hasReadSeq': 5, 'success': true},
            {'conversationID': 'sg_b', 'hasReadSeq': 99, 'success': true},
            {'conversationID': 'sg_other', 'hasReadSeq': 5, 'success': true},
          ]
        },
      }));
    }));
    final api = ConversationBatchReadApi();
    expect(
        await api.apply([
          const BatchReadTarget('sg_a', 5),
          const BatchReadTarget('sg_b', 6)
        ]),
        {'sg_a'});
    api.close();
  });

  test('replacement login cannot send requests using the captured session',
      () async {
    final api = ConversationBatchReadApi();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'other',
      'imToken': 'other-token',
      'chatToken': 'other-chat'
    }));
    expect(api.isCurrent, false);
    await expectLater(api.prepare('group'), throwsStateError);
    api.close();
  });
}
