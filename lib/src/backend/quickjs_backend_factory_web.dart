import 'quickjs_backend.dart';
import '../web/quickjs_web_backend.dart';

/// 创建 Flutter Web backend。
Future<QuickjsBackend> createQuickjsBackend() async {
  return WebQuickjsBackend.create();
}
