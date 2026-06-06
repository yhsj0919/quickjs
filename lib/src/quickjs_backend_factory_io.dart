import 'native/quickjs_native_backend.dart';
import 'quickjs_backend.dart';

Future<QuickjsBackend> createQuickjsBackend() async {
  return NativeQuickjsBackend();
}
