// 条件导出平台 backend factory。
// Dart 编译器会根据目标平台选择 io / web / stub 实现。
export 'backend_factory_stub.dart'
    if (dart.library.io) 'backend_factory_io.dart'
    if (dart.library.html) 'backend_factory_web.dart';
