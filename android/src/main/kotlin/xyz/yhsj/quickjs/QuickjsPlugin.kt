package xyz.yhsj.quickjs

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Registers the FFI plugin; QuickJS runs via native library. */
class QuickjsPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {}

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
