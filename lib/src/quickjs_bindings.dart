import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// C 侧 QuickjsRuntime 的不透明指针。
final class QuickjsRuntime extends Opaque {}

typedef QuickjsVersionNative = Pointer<Utf8> Function();
typedef QuickjsVersion = Pointer<Utf8> Function();

typedef QuickjsRuntimeNewNative = Pointer<QuickjsRuntime> Function();
typedef QuickjsRuntimeNew = Pointer<QuickjsRuntime> Function();

typedef QuickjsRuntimeFreeNative = Void Function(Pointer<QuickjsRuntime>);
typedef QuickjsRuntimeFree = void Function(Pointer<QuickjsRuntime>);

typedef QuickjsRuntimeSetMemoryLimitNative =
    Void Function(Pointer<QuickjsRuntime>, Int64);
typedef QuickjsRuntimeSetMemoryLimit =
    void Function(Pointer<QuickjsRuntime>, int);

typedef QuickjsRuntimeSetStackLimitNative =
    Void Function(Pointer<QuickjsRuntime>, Int64);
typedef QuickjsRuntimeSetStackLimit =
    void Function(Pointer<QuickjsRuntime>, int);

typedef QuickjsRuntimeSetCancelFlagNative =
    Void Function(Pointer<QuickjsRuntime>, Pointer<Int32>);
typedef QuickjsRuntimeSetCancelFlag =
    void Function(Pointer<QuickjsRuntime>, Pointer<Int32>);

typedef QuickjsEvalTimeoutNative =
    Pointer<Utf8> Function(Pointer<QuickjsRuntime>, Pointer<Utf8>, Int64);
typedef QuickjsEvalTimeout =
    Pointer<Utf8> Function(Pointer<QuickjsRuntime>, Pointer<Utf8>, int);

typedef QuickjsFreeStringNative = Void Function(Pointer<Utf8>);
typedef QuickjsFreeString = void Function(Pointer<Utf8>);

typedef QuickjsHostCallbackNative =
    Int64 Function(Int64 callbackId, Pointer<Utf8> argsJson);
typedef QuickjsHostCallback =
    int Function(int callbackId, Pointer<Utf8> argsJson);

typedef QuickjsRuntimeBindCallbackNative =
    Int32 Function(
      Pointer<QuickjsRuntime>,
      Int64,
      Pointer<Utf8>,
      Pointer<NativeFunction<QuickjsHostCallbackNative>>,
    );
typedef QuickjsRuntimeBindCallback =
    int Function(
      Pointer<QuickjsRuntime>,
      int,
      Pointer<Utf8>,
      Pointer<NativeFunction<QuickjsHostCallbackNative>>,
    );

typedef QuickjsEvalAsyncStartNative =
    Pointer<Utf8> Function(Pointer<QuickjsRuntime>, Pointer<Utf8>);
typedef QuickjsEvalAsyncStart =
    Pointer<Utf8> Function(Pointer<QuickjsRuntime>, Pointer<Utf8>);

typedef QuickjsEvalAsyncPollNative =
    Pointer<Utf8> Function(Pointer<QuickjsRuntime>);
typedef QuickjsEvalAsyncPoll = Pointer<Utf8> Function(Pointer<QuickjsRuntime>);

typedef QuickjsRuntimeResolveCallbackNative =
    Int32 Function(Pointer<QuickjsRuntime>, Int64, Int32, Pointer<Utf8>);
typedef QuickjsRuntimeResolveCallback =
    int Function(Pointer<QuickjsRuntime>, int, int, Pointer<Utf8>);

/// QuickJS native 动态库的 Dart FFI 绑定。
///
/// 这里只声明 ABI 函数，不持有 runtime 状态；runtime 生命周期由 worker 管理。
class QuickjsBindings {
  QuickjsBindings(DynamicLibrary lib)
    : version = lib.lookupFunction<QuickjsVersionNative, QuickjsVersion>(
        'quickjs_version',
      ),
      runtimeNew = lib
          .lookupFunction<QuickjsRuntimeNewNative, QuickjsRuntimeNew>(
            'quickjs_runtime_new',
          ),
      runtimeFree = lib
          .lookupFunction<QuickjsRuntimeFreeNative, QuickjsRuntimeFree>(
            'quickjs_runtime_free',
          ),
      runtimeSetMemoryLimit = lib
          .lookupFunction<
            QuickjsRuntimeSetMemoryLimitNative,
            QuickjsRuntimeSetMemoryLimit
          >('quickjs_runtime_set_memory_limit'),
      runtimeSetStackLimit = lib
          .lookupFunction<
            QuickjsRuntimeSetStackLimitNative,
            QuickjsRuntimeSetStackLimit
          >('quickjs_runtime_set_stack_limit'),
      runtimeSetCancelFlag = lib
          .lookupFunction<
            QuickjsRuntimeSetCancelFlagNative,
            QuickjsRuntimeSetCancelFlag
          >('quickjs_runtime_set_cancel_flag'),
      evalTimeout = lib
          .lookupFunction<QuickjsEvalTimeoutNative, QuickjsEvalTimeout>(
            'quickjs_eval_timeout',
          ),
      runtimeBindCallback = lib
          .lookupFunction<
            QuickjsRuntimeBindCallbackNative,
            QuickjsRuntimeBindCallback
          >('quickjs_runtime_bind_callback'),
      evalAsyncStart = lib
          .lookupFunction<QuickjsEvalAsyncStartNative, QuickjsEvalAsyncStart>(
            'quickjs_eval_async_start',
          ),
      evalAsyncPoll = lib
          .lookupFunction<QuickjsEvalAsyncPollNative, QuickjsEvalAsyncPoll>(
            'quickjs_eval_async_poll',
          ),
      runtimeResolveCallback = lib
          .lookupFunction<
            QuickjsRuntimeResolveCallbackNative,
            QuickjsRuntimeResolveCallback
          >('quickjs_runtime_resolve_callback'),
      freeString = lib
          .lookupFunction<QuickjsFreeStringNative, QuickjsFreeString>(
            'quickjs_free_string',
          );

  final QuickjsVersion version;
  final QuickjsRuntimeNew runtimeNew;
  final QuickjsRuntimeFree runtimeFree;
  final QuickjsRuntimeSetMemoryLimit runtimeSetMemoryLimit;
  final QuickjsRuntimeSetStackLimit runtimeSetStackLimit;
  final QuickjsRuntimeSetCancelFlag runtimeSetCancelFlag;
  final QuickjsEvalTimeout evalTimeout;
  final QuickjsRuntimeBindCallback runtimeBindCallback;
  final QuickjsEvalAsyncStart evalAsyncStart;
  final QuickjsEvalAsyncPoll evalAsyncPoll;
  final QuickjsRuntimeResolveCallback runtimeResolveCallback;
  final QuickjsFreeString freeString;

  static DynamicLibrary open() {
    if (Platform.isWindows) {
      return _openWindows();
    }
    if (Platform.isLinux || Platform.isAndroid) {
      return DynamicLibrary.open('libquickjs.so');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError(
      'QuickJS native bindings are not available on ${Platform.operatingSystem}',
    );
  }

  static DynamicLibrary _openWindows() {
    const dllName = 'quickjs.dll';
    final configuredDllPath = Platform.environment['QUICKJS_DLL_PATH'];
    final candidates = <String>[
      dllName,
      ?configuredDllPath,
      // Flutter 测试进程和 example 构建产物的 DLL 位置不固定，这里按常见路径兜底查找。
      '${File(Platform.resolvedExecutable).parent.path}\\$dllName',
      '${Directory.current.path}\\$dllName',
      ..._windowsBuildOutputCandidates(dllName),
    ];

    Object? lastError;
    for (final candidate in candidates) {
      try {
        return DynamicLibrary.open(candidate);
      } catch (error) {
        lastError = error;
      }
    }

    throw ArgumentError(
      'Failed to load $dllName. Build the Windows native library first '
      'or set QUICKJS_DLL_PATH to the full DLL path. Last error: $lastError',
    );
  }

  static Iterable<String> _windowsBuildOutputCandidates(String dllName) sync* {
    final roots = <String>[
      Directory.current.path,
      '${Directory.current.path}\\example',
    ];
    const configurations = ['Debug', 'Profile', 'Release', 'RelWithDebInfo'];

    for (final root in roots) {
      for (final configuration in configurations) {
        yield '$root\\build\\windows\\x64\\plugins\\quickjs'
            '\\quickjs_native\\$configuration\\$dllName';
        yield '$root\\build\\windows\\x64\\runner\\$configuration\\$dllName';
      }
    }
  }
}
