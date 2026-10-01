import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
void main() {
  test('credentials preserve new and legacy IM IDs without business identity', () {
    for (final id in ['im_random_123', '2138014845', 'm00000001']) {
      final cert = LoginCertificate.fromJson({'userID': id, 'imToken': 'secret-im', 'chatToken': 'secret-chat', 'business_uid': 'private', 'account': 'display'});
      expect(cert.userID, id);
      expect(cert.toJson(), {'userID': id, 'imToken': 'secret-im', 'chatToken': 'secret-chat'});
      expect(cert.toString(), isNot(contains(id)));
      expect(cert.toString(), isNot(contains('secret')));
    }
  });
}
