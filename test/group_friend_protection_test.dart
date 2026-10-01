import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/chat/group_setup/group_manage/group_friend_protection_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({'userID':'me','chatToken':'chat'}));
  });
  test('uses Chat state and reconciles PUT without response data', () async {
    final requests = <RequestOptions>[];
    var protected = false;
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (r,h) {
      requests.add(r);
      if (r.method == 'PUT') protected = r.data['protect'] as bool;
      h.resolve(Response(requestOptions:r, data:{'errCode':0,
        if(r.method == 'GET') 'data':{'protect':protected,'canManage':true}}));
    }));
    final store = GroupFriendProtectionStore('@group',client:client,notify:(_){});
    await store.refresh();
    expect(store.ready.value,true);
    await store.setProtected(true);
    expect(requests.map((r)=>r.method),['GET','PUT','GET']);
    expect(requests[1].data,{'protect':true});
    expect(requests[1].headers['token'],'chat');
    expect(store.protect.value,true);
    store.dispose();
  });
  test('ordinary member cannot write and read failure invalidates state', () async {
    var fail = false;
    final requests = <RequestOptions>[];
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest:(r,h) {
      requests.add(r);
      h.resolve(Response(requestOptions:r,data: fail ? {'errCode':20020} :
        {'errCode':0,'data':{'protect':true,'canManage':false}}));
    }));
    final store = GroupFriendProtectionStore('group',client:client,notify:(_){});
    await store.refresh();
    await store.setProtected(false);
    expect(requests.length,1);
    fail = true;
    await store.refresh();
    expect(store.ready.value,false);
    expect(store.failed.value,true);
    await store.setProtected(false);
    expect(requests.length,2);
    store.dispose();
  });
}
