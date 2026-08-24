#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif
import lemon_js_native

public class LemonJsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Keep the native bridge object linked into the final app. Dart resolves
    // the remaining exported FFI functions from the process symbol table.
    _ = quickjs_version()
  }
}
