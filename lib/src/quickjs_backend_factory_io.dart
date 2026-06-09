import 'native/quickjs_native_backend.dart';
import 'quickjs_backend.dart';

/// 创建 native 平台 backend。
Future<QuickjsBackend> createQuickjsBackend() async {
  return NativeQuickjsBackend();
}
