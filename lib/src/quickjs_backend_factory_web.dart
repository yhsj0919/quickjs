import 'quickjs_backend.dart';
import 'web/quickjs_web_backend.dart';

Future<QuickjsBackend> createQuickjsBackend() async {
  return WebQuickjsBackend.create();
}
