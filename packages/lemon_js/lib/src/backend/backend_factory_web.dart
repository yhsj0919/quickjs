import 'backend.dart';
import '../web/web_backend.dart';

/// 创建 Flutter Web backend。
Future<JsBackend> createJsBackend() async {
  return WebJsBackend.create();
}
