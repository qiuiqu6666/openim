import 'dart:ffi';

bool supportsNativeMapAbi(Abi abi) =>
    abi != Abi.androidX64 && abi != Abi.androidIA32;

bool get nativeAvailable => supportsNativeMapAbi(Abi.current());
