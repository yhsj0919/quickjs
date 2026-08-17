import 'backend.dart';

/// 非 io / web 平台的兜底实现。
Future<JsBackend> createJsBackend() {
  throw UnsupportedError('QuickJS is not supported on this platform');
}
