import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
class _App extends GetxController implements AppController {
 @override
 dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Callbacks extends GetxController with IMCallback {}
void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 test('connecting before SDK userID initialization does not block login', () async {
  SharedPreferences.setMockInitialValues({});
  await DataSp.init();
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({'userID':'new-login','imToken':'im','chatToken':'chat'}));
  // Deliberately do not assign OpenIM.iMManager.userID: native login has not run.
  expect(() => OpenIM.iMManager.userID, throwsA(isA<Error>()));
  Get.testMode = true;
  Get.put<AppController>(_App());
  final callbacks = _Callbacks();
  expect(() => callbacks.imSdkStatus(IMSdkStatus.connecting), returnsNormally);
  callbacks.imSdkStatus(IMSdkStatus.syncStart, reInstall: true);
  expect(callbacks.initialSyncState?.reInstall, isTrue);
  callbacks.close();
 });
}
