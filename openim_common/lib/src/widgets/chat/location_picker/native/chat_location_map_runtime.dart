import 'chat_location_map_runtime_stub.dart'
    if (dart.library.ffi) 'chat_location_map_runtime_ffi.dart' as runtime;

/// Check the running process, not advertised ABIs (which may include ARM
/// translation). The bundled AMap renderer ships ARM libraries only.
class ChatLocationMapRuntime {
  static Future<bool> nativeAvailable() async => runtime.nativeAvailable;
}
