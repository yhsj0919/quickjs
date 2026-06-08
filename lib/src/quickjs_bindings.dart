import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class QuickjsRuntime extends Opaque {}

typedef QuickjsVersionNative = Pointer<Utf8> Function();
typedef QuickjsVersion = Pointer<Utf8> Function();

typedef QuickjsRuntimeNewNative = Pointer<QuickjsRuntime> Function();
typedef QuickjsRuntimeNew = Pointer<QuickjsRuntime> Function();

typedef QuickjsRuntimeFreeNative = Void Function(Pointer<QuickjsRuntime>);
typedef QuickjsRuntimeFree = void Function(Pointer<QuickjsRuntime>);

typedef QuickjsRuntimeSetCancelFlagNative =
    Void Function(Pointer<QuickjsRuntime>, Pointer<Int32>);
typedef QuickjsRuntimeSetCancelFlag =
    void Function(Pointer<QuickjsRuntime>, Pointer<Int32>);

typedef QuickjsEvalNative =
    Pointer<Utf8> Function(Pointer<QuickjsRuntime>, Pointer<Utf8>);
typedef QuickjsEval =
    Pointer<Utf8> Function(Pointer<QuickjsRuntime>, Pointer<Utf8>);

typedef QuickjsEvalTimeoutNative =
    Pointer<Utf8> Function(Pointer<QuickjsRuntime>, Pointer<Utf8>, Int64);
typedef QuickjsEvalTimeout =
    Pointer<Utf8> Function(Pointer<QuickjsRuntime>, Pointer<Utf8>, int);

typedef QuickjsFreeStringNative = Void Function(Pointer<Utf8>);
typedef QuickjsFreeString = void Function(Pointer<Utf8>);

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
      runtimeSetCancelFlag =
          lib.lookupFunction<
            QuickjsRuntimeSetCancelFlagNative,
            QuickjsRuntimeSetCancelFlag
          >('quickjs_runtime_set_cancel_flag'),
      eval = lib.lookupFunction<QuickjsEvalNative, QuickjsEval>('quickjs_eval'),
      evalTimeout =
          lib.lookupFunction<QuickjsEvalTimeoutNative, QuickjsEvalTimeout>(
            'quickjs_eval_timeout',
          ),
      freeString = lib
          .lookupFunction<QuickjsFreeStringNative, QuickjsFreeString>(
            'quickjs_free_string',
          );

  final QuickjsVersion version;
  final QuickjsRuntimeNew runtimeNew;
  final QuickjsRuntimeFree runtimeFree;
  final QuickjsRuntimeSetCancelFlag runtimeSetCancelFlag;
  final QuickjsEval eval;
  final QuickjsEvalTimeout evalTimeout;
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
