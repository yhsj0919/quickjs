import '../native/native_backend.dart';
import 'backend.dart';

/// 创建 native 平台 backend。
Future<JsBackend> createJsBackend() async {
  return NativeJsBackend();
}
