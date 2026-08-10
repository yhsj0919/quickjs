// 条件导出平台 backend factory。
// Dart 编译器会根据目标平台选择 io / web / stub 实现。
export 'quickjs_backend_factory_stub.dart'
    if (dart.library.io) 'quickjs_backend_factory_io.dart'
    if (dart.library.html) 'quickjs_backend_factory_web.dart';
