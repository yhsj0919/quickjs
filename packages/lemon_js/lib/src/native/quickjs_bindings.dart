import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// C 侧 JsRuntime 的不透明指针。
final class JsRuntime extends Opaque {}

final class JsContext extends Opaque {}

typedef JsVersionNative = Pointer<Utf8> Function();
typedef JsVersion = Pointer<Utf8> Function();

typedef JsRuntimeNewNative = Pointer<JsRuntime> Function();
typedef JsRuntimeNew = Pointer<JsRuntime> Function();

typedef JsRuntimeFreeNative = Void Function(Pointer<JsRuntime>);
typedef JsRuntimeFree = void Function(Pointer<JsRuntime>);
typedef JsContextNewNative = Pointer<JsContext> Function(Pointer<JsRuntime>);
typedef JsContextNew = Pointer<JsContext> Function(Pointer<JsRuntime>);
typedef JsContextFreeNative = Void Function(Pointer<JsContext>);
typedef JsContextFree = void Function(Pointer<JsContext>);
typedef JsContextEvalTimeoutNamedNative =
    Pointer<Utf8> Function(
      Pointer<JsContext>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int64,
    );
typedef JsContextEvalTimeoutNamed =
    Pointer<Utf8> Function(
      Pointer<JsContext>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
    );
typedef JsContextEvalModuleNative =
    Pointer<Utf8> Function(
      Pointer<JsContext>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef JsContextEvalModule =
    Pointer<Utf8> Function(
      Pointer<JsContext>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef JsContextBindCallbackNative =
    Int32 Function(
      Pointer<JsContext>,
      Int64,
      Pointer<Utf8>,
      Pointer<NativeFunction<JsHostCallbackNative>>,
    );
typedef JsContextBindCallback =
    int Function(
      Pointer<JsContext>,
      int,
      Pointer<Utf8>,
      Pointer<NativeFunction<JsHostCallbackNative>>,
    );
typedef JsContextEvalAsyncStartNamedNative =
    Pointer<Utf8> Function(Pointer<JsContext>, Pointer<Utf8>, Pointer<Utf8>);
typedef JsContextEvalAsyncStartNamed =
    Pointer<Utf8> Function(Pointer<JsContext>, Pointer<Utf8>, Pointer<Utf8>);
typedef JsContextEvalAsyncPollNative =
    Pointer<Utf8> Function(Pointer<JsContext>);
typedef JsContextEvalAsyncPoll = Pointer<Utf8> Function(Pointer<JsContext>);
typedef JsContextPumpTimersNative = Int64 Function(Pointer<JsContext>);
typedef JsContextPumpTimers = int Function(Pointer<JsContext>);
typedef JsContextBindSinkNative =
    Int32 Function(Pointer<JsContext>, Int64, Pointer<Utf8>);
typedef JsContextBindSink =
    int Function(Pointer<JsContext>, int, Pointer<Utf8>);

typedef JsRuntimeSetMemoryLimitNative =
    Void Function(Pointer<JsRuntime>, Int64);
typedef JsRuntimeSetMemoryLimit = void Function(Pointer<JsRuntime>, int);

typedef JsRuntimeSetStackLimitNative = Void Function(Pointer<JsRuntime>, Int64);
typedef JsRuntimeSetStackLimit = void Function(Pointer<JsRuntime>, int);

typedef JsRuntimeSetCancelFlagNative =
    Void Function(Pointer<JsRuntime>, Pointer<Int32>);
typedef JsRuntimeSetCancelFlag =
    void Function(Pointer<JsRuntime>, Pointer<Int32>);
typedef JsRuntimePumpTimersNative = Int64 Function(Pointer<JsRuntime>);
typedef JsRuntimePumpTimers = int Function(Pointer<JsRuntime>);

typedef JsEvalTimeoutNative =
    Pointer<Utf8> Function(Pointer<JsRuntime>, Pointer<Utf8>, Int64);
typedef JsEvalTimeout =
    Pointer<Utf8> Function(Pointer<JsRuntime>, Pointer<Utf8>, int);

typedef JsEvalTimeoutNamedNative =
    Pointer<Utf8> Function(
      Pointer<JsRuntime>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int64,
    );
typedef JsEvalTimeoutNamed =
    Pointer<Utf8> Function(
      Pointer<JsRuntime>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
    );

typedef JsEvalModuleNative =
    Pointer<Utf8> Function(
      Pointer<JsRuntime>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef JsEvalModule =
    Pointer<Utf8> Function(
      Pointer<JsRuntime>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );

typedef JsFreeStringNative = Void Function(Pointer<Utf8>);
typedef JsFreeString = void Function(Pointer<Utf8>);

typedef JsHostCallbackNative =
    Int64 Function(Int64 callbackId, Pointer<Utf8> argsJson);
typedef JsHostCallback = int Function(int callbackId, Pointer<Utf8> argsJson);

typedef JsRuntimeBindCallbackNative =
    Int32 Function(
      Pointer<JsRuntime>,
      Int64,
      Pointer<Utf8>,
      Pointer<NativeFunction<JsHostCallbackNative>>,
    );
typedef JsRuntimeBindCallback =
    int Function(
      Pointer<JsRuntime>,
      int,
      Pointer<Utf8>,
      Pointer<NativeFunction<JsHostCallbackNative>>,
    );

typedef JsEvalAsyncStartNative =
    Pointer<Utf8> Function(Pointer<JsRuntime>, Pointer<Utf8>);
typedef JsEvalAsyncStart =
    Pointer<Utf8> Function(Pointer<JsRuntime>, Pointer<Utf8>);

typedef JsEvalAsyncStartNamedNative =
    Pointer<Utf8> Function(Pointer<JsRuntime>, Pointer<Utf8>, Pointer<Utf8>);
typedef JsEvalAsyncStartNamed =
    Pointer<Utf8> Function(Pointer<JsRuntime>, Pointer<Utf8>, Pointer<Utf8>);

typedef JsEvalAsyncPollNative = Pointer<Utf8> Function(Pointer<JsRuntime>);
typedef JsEvalAsyncPoll = Pointer<Utf8> Function(Pointer<JsRuntime>);

typedef JsRuntimeResolveCallbackNative =
    Int32 Function(Pointer<JsRuntime>, Int64, Int32, Pointer<Utf8>);
typedef JsRuntimeResolveCallback =
    int Function(Pointer<JsRuntime>, int, int, Pointer<Utf8>);

typedef JsHostStreamPullNative = Int64 Function(Int64 streamId);
typedef JsHostStreamPull = int Function(int streamId);

typedef JsHostStreamCancelNative = Void Function(Int64 streamId);
typedef JsHostStreamCancel = void Function(int streamId);

typedef JsHostSinkActionNative =
    Int64 Function(
      Int64 sinkId,
      Pointer<Utf8> action,
      Pointer<Utf8> payloadJson,
    );
typedef JsHostSinkAction =
    int Function(int sinkId, Pointer<Utf8> action, Pointer<Utf8> payloadJson);

typedef JsRuntimeSetStreamHandlersNative =
    Void Function(
      Pointer<JsRuntime>,
      Pointer<NativeFunction<JsHostStreamPullNative>>,
      Pointer<NativeFunction<JsHostStreamCancelNative>>,
      Pointer<NativeFunction<JsHostSinkActionNative>>,
    );
typedef JsRuntimeSetStreamHandlers =
    void Function(
      Pointer<JsRuntime>,
      Pointer<NativeFunction<JsHostStreamPullNative>>,
      Pointer<NativeFunction<JsHostStreamCancelNative>>,
      Pointer<NativeFunction<JsHostSinkActionNative>>,
    );

typedef JsRuntimeResolveStreamPullNative =
    Int32 Function(Pointer<JsRuntime>, Int64, Int32, Pointer<Utf8>);
typedef JsRuntimeResolveStreamPull =
    int Function(Pointer<JsRuntime>, int, int, Pointer<Utf8>);

typedef JsRuntimeResolveSinkActionNative =
    Int32 Function(Pointer<JsRuntime>, Int64, Int32, Pointer<Utf8>);
typedef JsRuntimeResolveSinkAction =
    int Function(Pointer<JsRuntime>, int, int, Pointer<Utf8>);

typedef JsRuntimeBindSinkNative =
    Int32 Function(Pointer<JsRuntime>, Int64, Pointer<Utf8>);
typedef JsRuntimeBindSink =
    int Function(Pointer<JsRuntime>, int, Pointer<Utf8>);

/// QuickJS native 动态库的 Dart FFI 绑定。
///
/// 这里只声明 ABI 函数，不持有 runtime 状态；runtime 生命周期由 worker 管理。
class JsBindings {
  JsBindings(DynamicLibrary lib)
    : version = lib.lookupFunction<JsVersionNative, JsVersion>(
        'quickjs_version',
      ),
      runtimeNew = lib.lookupFunction<JsRuntimeNewNative, JsRuntimeNew>(
        'quickjs_runtime_new',
      ),
      runtimeFree = lib.lookupFunction<JsRuntimeFreeNative, JsRuntimeFree>(
        'quickjs_runtime_free',
      ),
      contextNew = lib.lookupFunction<JsContextNewNative, JsContextNew>(
        'quickjs_context_new',
      ),
      contextFree = lib.lookupFunction<JsContextFreeNative, JsContextFree>(
        'quickjs_context_free',
      ),
      contextEvalTimeoutNamed = lib
          .lookupFunction<
            JsContextEvalTimeoutNamedNative,
            JsContextEvalTimeoutNamed
          >('quickjs_context_eval_timeout_named'),
      contextEvalModule = lib
          .lookupFunction<JsContextEvalModuleNative, JsContextEvalModule>(
            'quickjs_context_eval_module',
          ),
      contextBindCallback = lib
          .lookupFunction<JsContextBindCallbackNative, JsContextBindCallback>(
            'quickjs_context_bind_callback',
          ),
      contextEvalAsyncStartNamed = lib
          .lookupFunction<
            JsContextEvalAsyncStartNamedNative,
            JsContextEvalAsyncStartNamed
          >('quickjs_context_eval_async_start_named'),
      contextEvalAsyncPoll = lib
          .lookupFunction<JsContextEvalAsyncPollNative, JsContextEvalAsyncPoll>(
            'quickjs_context_eval_async_poll',
          ),
      contextPumpTimers = lib
          .lookupFunction<JsContextPumpTimersNative, JsContextPumpTimers>(
            'quickjs_context_pump_timers',
          ),
      contextBindSink = lib
          .lookupFunction<JsContextBindSinkNative, JsContextBindSink>(
            'quickjs_context_bind_sink',
          ),
      runtimeSetMemoryLimit = lib
          .lookupFunction<
            JsRuntimeSetMemoryLimitNative,
            JsRuntimeSetMemoryLimit
          >('quickjs_runtime_set_memory_limit'),
      runtimeSetStackLimit = lib
          .lookupFunction<JsRuntimeSetStackLimitNative, JsRuntimeSetStackLimit>(
            'quickjs_runtime_set_stack_limit',
          ),
      runtimeSetCancelFlag = lib
          .lookupFunction<JsRuntimeSetCancelFlagNative, JsRuntimeSetCancelFlag>(
            'quickjs_runtime_set_cancel_flag',
          ),
      runtimePumpTimers = lib
          .lookupFunction<JsRuntimePumpTimersNative, JsRuntimePumpTimers>(
            'quickjs_runtime_pump_timers',
          ),
      evalTimeout = lib.lookupFunction<JsEvalTimeoutNative, JsEvalTimeout>(
        'quickjs_eval_timeout',
      ),
      evalTimeoutNamed = lib
          .lookupFunction<JsEvalTimeoutNamedNative, JsEvalTimeoutNamed>(
            'quickjs_eval_timeout_named',
          ),
      evalModule = lib.lookupFunction<JsEvalModuleNative, JsEvalModule>(
        'quickjs_eval_module',
      ),
      runtimeBindCallback = lib
          .lookupFunction<JsRuntimeBindCallbackNative, JsRuntimeBindCallback>(
            'quickjs_runtime_bind_callback',
          ),
      evalAsyncStart = lib
          .lookupFunction<JsEvalAsyncStartNative, JsEvalAsyncStart>(
            'quickjs_eval_async_start',
          ),
      evalAsyncStartNamed = lib
          .lookupFunction<JsEvalAsyncStartNamedNative, JsEvalAsyncStartNamed>(
            'quickjs_eval_async_start_named',
          ),
      evalAsyncPoll = lib
          .lookupFunction<JsEvalAsyncPollNative, JsEvalAsyncPoll>(
            'quickjs_eval_async_poll',
          ),
      runtimeResolveCallback = lib
          .lookupFunction<
            JsRuntimeResolveCallbackNative,
            JsRuntimeResolveCallback
          >('quickjs_runtime_resolve_callback'),
      runtimeSetStreamHandlers = lib
          .lookupFunction<
            JsRuntimeSetStreamHandlersNative,
            JsRuntimeSetStreamHandlers
          >('quickjs_runtime_set_stream_handlers'),
      runtimeResolveStreamPull = lib
          .lookupFunction<
            JsRuntimeResolveStreamPullNative,
            JsRuntimeResolveStreamPull
          >('quickjs_runtime_resolve_stream_pull'),
      runtimeResolveSinkAction = lib
          .lookupFunction<
            JsRuntimeResolveSinkActionNative,
            JsRuntimeResolveSinkAction
          >('quickjs_runtime_resolve_sink_action'),
      runtimeBindSink = lib
          .lookupFunction<JsRuntimeBindSinkNative, JsRuntimeBindSink>(
            'quickjs_runtime_bind_sink',
          ),
      freeString = lib.lookupFunction<JsFreeStringNative, JsFreeString>(
        'quickjs_free_string',
      );

  final JsVersion version;
  final JsRuntimeNew runtimeNew;
  final JsRuntimeFree runtimeFree;
  final JsContextNew contextNew;
  final JsContextFree contextFree;
  final JsContextEvalTimeoutNamed contextEvalTimeoutNamed;
  final JsContextEvalModule contextEvalModule;
  final JsContextBindCallback contextBindCallback;
  final JsContextEvalAsyncStartNamed contextEvalAsyncStartNamed;
  final JsContextEvalAsyncPoll contextEvalAsyncPoll;
  final JsContextPumpTimers contextPumpTimers;
  final JsContextBindSink contextBindSink;
  final JsRuntimeSetMemoryLimit runtimeSetMemoryLimit;
  final JsRuntimeSetStackLimit runtimeSetStackLimit;
  final JsRuntimeSetCancelFlag runtimeSetCancelFlag;
  final JsRuntimePumpTimers runtimePumpTimers;
  final JsEvalTimeout evalTimeout;
  final JsEvalTimeoutNamed evalTimeoutNamed;
  final JsEvalModule evalModule;
  final JsRuntimeBindCallback runtimeBindCallback;
  final JsEvalAsyncStart evalAsyncStart;
  final JsEvalAsyncStartNamed evalAsyncStartNamed;
  final JsEvalAsyncPoll evalAsyncPoll;
  final JsRuntimeResolveCallback runtimeResolveCallback;
  final JsRuntimeSetStreamHandlers runtimeSetStreamHandlers;
  final JsRuntimeResolveStreamPull runtimeResolveStreamPull;
  final JsRuntimeResolveSinkAction runtimeResolveSinkAction;
  final JsRuntimeBindSink runtimeBindSink;
  final JsFreeString freeString;

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
// ignore_for_file: public_member_api_docs
