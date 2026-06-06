import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../quickjs_backend.dart';
import '../quickjs_bindings.dart';
import '../quickjs_runtime_base.dart';

/// FFI backend for mobile and desktop.
class NativeQuickjsBackend implements QuickjsBackend {
  NativeQuickjsBackend([QuickjsBindings? bindings])
    : bindings = bindings ?? QuickjsBindings(QuickjsBindings.open());

  final QuickjsBindings bindings;

  @override
  String get quickjsVersion => bindings.version().toDartString();

  @override
  Future<QuickjsJsRuntimeBase> createRuntime() async {
    final handle = bindings.runtimeNew();
    if (handle == nullptr) {
      throw StateError('Failed to create QuickJS runtime');
    }
    return NativeQuickjsJsRuntime(bindings, handle);
  }

  @override
  Future<String> evaluate(String code) async {
    final runtime = await createRuntime();
    try {
      return runtime.evaluate(code);
    } finally {
      runtime.dispose();
    }
  }
}

final class NativeQuickjsJsRuntime implements QuickjsJsRuntimeBase {
  NativeQuickjsJsRuntime(this._bindings, this._handle);

  final QuickjsBindings _bindings;
  final Pointer<QuickjsRuntime> _handle;
  bool _closed = false;

  @override
  String evaluate(String code) {
    _ensureOpen();
    final codePtr = code.toNativeUtf8();
    final resultPtr = _bindings.eval(_handle, codePtr);
    calloc.free(codePtr);
    if (resultPtr == nullptr) {
      throw StateError('QuickJS eval returned null');
    }
    try {
      return resultPtr.toDartString();
    } finally {
      _bindings.freeString(resultPtr);
    }
  }

  @override
  void dispose() {
    if (_closed) {
      return;
    }
    _bindings.runtimeFree(_handle);
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('QuickJS runtime is closed');
    }
  }
}
