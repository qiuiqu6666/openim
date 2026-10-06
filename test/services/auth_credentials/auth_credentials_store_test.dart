import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/auth_credentials/auth_credentials_store.dart';

class _PausedWriteStorage extends FlutterSecureStorage {
  final started = Completer<void>();
  final release = Completer<void>();
  bool _paused = false;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == AuthCredentialsStore.credentialsKey && !_paused) {
      _paused = true;
      started.complete();
      await release.future;
    }
    await super.write(key: key, value: value);
  }
}

Future<bool> _save(AuthCredentialsStore store,
        {String account = '13800138000',
        String? password = 'password1',
        bool Function()? isCurrent}) =>
    store.saveSuccessful(
      account: account,
      areaCode: '+86',
      loginType: 0,
      password: password,
      rememberPassword: true,
      isCurrent: isCurrent ?? () => true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('successful password login restores encrypted account and password',
      () async {
    final store = AuthCredentialsStore();
    expect((await store.load()).rememberPassword, isTrue);
    expect(await _save(store), isTrue);
    final restored = await AuthCredentialsStore().load();
    expect(restored.account, '13800138000');
    expect(restored.areaCode, '+86');
    expect(restored.loginType, 0);
    expect(restored.password, 'password1');
  });

  test(
      'turning off remember deletes the saved password and persists preference',
      () async {
    final store = AuthCredentialsStore();
    await _save(store);
    await store.setRememberPassword(false);
    expect(await _save(store, password: 'new-password'), isTrue);
    final restored = await AuthCredentialsStore().load();
    expect(restored.account, '13800138000');
    expect(restored.password, isNull);
    expect(restored.rememberPassword, isFalse);
    final raw = await const FlutterSecureStorage()
        .read(key: AuthCredentialsStore.credentialsKey);
    expect(raw, isNot(contains('password')));
  });

  test('SMS for the same account preserves its remembered password', () async {
    final store = AuthCredentialsStore();
    await _save(store);
    await _save(store, password: null);
    expect((await store.load()).password, 'password1');
  });

  test('SMS for another account clears the previous account password',
      () async {
    final store = AuthCredentialsStore();
    await _save(store);
    await _save(store, account: '13900139000', password: null);
    final restored = await store.load();
    expect(restored.account, '13900139000');
    expect(restored.password, isNull);
  });

  test('superseded write rolls back before the newer account saves', () async {
    final storage = _PausedWriteStorage();
    final store = AuthCredentialsStore(storage: storage);
    var current = true;
    final old = _save(store, isCurrent: () => current);
    await storage.started.future;
    current = false;
    final next =
        _save(store, account: '13900139000', password: 'later-password');
    storage.release.complete();
    expect(await old, isFalse);
    expect(await next, isTrue);
    final restored = await store.load();
    expect(restored.account, '13900139000');
    expect(restored.password, 'later-password');
  });

  test('turning remember off during a write leaves no password', () async {
    final storage = _PausedWriteStorage();
    final store = AuthCredentialsStore(storage: storage);
    final login = _save(store);
    await storage.started.future;
    final disable = store.setRememberPassword(false);
    storage.release.complete();
    await login;
    await disable;
    final restored = await store.load();
    expect(restored.password, isNull);
    expect(restored.rememberPassword, isFalse);
  });

  test('a cancelled write preserves previously remembered credentials',
      () async {
    await _save(AuthCredentialsStore(), account: '13900139000');
    final storage = _PausedWriteStorage();
    final store = AuthCredentialsStore(storage: storage);
    var current = true;
    final pending =
        _save(store, password: 'cancelled-password', isCurrent: () => current);
    await storage.started.future;
    current = false;
    storage.release.complete();
    expect(await pending, isFalse);
    final restored = await store.load();
    expect(restored.account, '13900139000');
    expect(restored.password, 'password1');
  });

  test('password reset updates only matching remembered phone credentials',
      () async {
    final store = AuthCredentialsStore();
    await _save(store);
    Future<bool> reset(String account) => store.updatePasswordIfRemembered(
          account: account,
          areaCode: '+86',
          password: 'reset-password',
          isCurrent: () => true,
        );
    expect(await reset('13900139000'), isFalse);
    expect((await store.load()).password, 'password1');
    expect(await reset('13800138000'), isTrue);
    expect((await store.load()).password, 'reset-password');
    await store.setRememberPassword(false);
    expect(await reset('13800138000'), isFalse);
    expect((await store.load()).password, isNull);
  });

  test('corrupt saved data safely falls back to empty credentials', () async {
    FlutterSecureStorage.setMockInitialValues({
      AuthCredentialsStore.credentialsKey: '{invalid json',
      AuthCredentialsStore.rememberKey: 'false',
    });
    final restored = await AuthCredentialsStore().load();
    expect(restored.account, isEmpty);
    expect(restored.password, isNull);
    expect(restored.rememberPassword, isFalse);
  });
}
