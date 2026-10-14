import 'dart:ffi';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/chat/location_picker/native/chat_location_map_runtime_ffi.dart';

void main() {
  test('x86 Android processes avoid the ARM-only AMap engine', () {
    expect(supportsNativeMapAbi(Abi.androidX64), isFalse);
    expect(supportsNativeMapAbi(Abi.androidIA32), isFalse);
  });
  test('ARM Android and iOS keep their existing native maps', () {
    expect(supportsNativeMapAbi(Abi.androidArm64), isTrue);
    expect(supportsNativeMapAbi(Abi.androidArm), isTrue);
    expect(supportsNativeMapAbi(Abi.iosArm64), isTrue);
  });
}
