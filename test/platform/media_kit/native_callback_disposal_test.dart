// The fake overrides the generated libmpv C API names.
// ignore_for_file: non_constant_identifier_names
import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/generated/libmpv/bindings.dart';
import 'package:media_kit/src/player/native/core/initializer_native_callable.dart';

class FakeMpv extends MPV {
  FakeMpv() : super(DynamicLibrary.process());

  final event = calloc<mpv_event>();
  final handle = Pointer<mpv_handle>.fromAddress(1234);
  Pointer<NativeFunction<Void Function(Pointer<Void>)>> wakeup = nullptr;
  Pointer<Void> userData = nullptr;
  int reads = 0;
  int unregisters = 0;

  @override
  Pointer<mpv_handle> mpv_create() => handle;

  @override
  int mpv_initialize(Pointer<mpv_handle> ctx) => 0;

  @override
  void mpv_set_wakeup_callback(
    Pointer<mpv_handle> ctx,
    Pointer<NativeFunction<Void Function(Pointer<Void>)>> cb,
    Pointer<Void> data,
  ) {
    wakeup = cb;
    userData = data;
    if (cb == nullptr) unregisters++;
  }

  @override
  Pointer<mpv_event> mpv_wait_event(Pointer<mpv_handle> ctx, double timeout) {
    reads++;
    event.ref.event_id = mpv_event_id.MPV_EVENT_START_FILE;
    return event;
  }

  void emit() {
    if (wakeup != nullptr) {
      wakeup.asFunction<void Function(Pointer<Void>)>()(userData);
    }
  }
}

void main() {
  test('unregisters native wakeup and drains an in-flight event before closing',
      () async {
    final mpv = FakeMpv();
    addTearDown(() => calloc.free(mpv.event));
    final initializer = InitializerNativeCallable(mpv);
    final entered = Completer<void>();
    final resume = Completer<void>();
    final handle = await initializer.create((event) async {
      entered.complete();
      await resume.future;
    });
    mpv.emit();
    await entered.future.timeout(const Duration(seconds: 5));
    // A second wakeup can already be queued when teardown starts.
    mpv.emit();
    var finished = false;
    final closing = initializer.dispose(handle).then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(mpv.wakeup, nullptr);
    expect(mpv.unregisters, 1);
    expect(finished, isFalse);
    resume.complete();
    await closing;
    await Future<void>.delayed(Duration.zero);
    expect(mpv.reads, 1,
        reason: 'No native reads after the event loop is retired');
    // Shutdown events have no native callback to invoke after disposal.
    mpv.emit();
    expect(mpv.reads, 1);
  });
}
