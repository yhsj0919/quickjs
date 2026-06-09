import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('globalThis')
external JSObject get _globalThis;

/// Dart JS interop 访问 `Object.hasOwn` 的最小声明。
@JS('Object')
extension type _JSObjectStatic(JSObject _) implements JSObject {
  external static bool hasOwn(JSObject o, JSString prop);
}

/// `assets/web/quickjs_web.js` 暴露给 Dart 的全局 host API。
@JS('quickjsNgWeb')
extension type QuickjsWebHost(JSObject _) implements JSObject {
  external JSPromise<JSString> ensureInitialized(
    JSString wasmUrl,
    JSString bridgeModuleUrl,
    JSString workerScriptUrl,
  );
  external JSString quickjsVersion();
  external JSPromise<JSNumber> runtimeNew();
  external JSPromise<JSString> runtimeEval(
    JSNumber id,
    JSString code, [
    JSNumber? timeoutMs,
  ]);
  external JSPromise<JSAny?> runtimeStop();
  external JSPromise<JSAny?> runtimeDispose(JSNumber id);
}

@JS('quickjsNgWeb')
external QuickjsWebHost get _quickjsNgWeb;

/// 将 package asset 路径转换成 Flutter Web 运行时可加载的 URL。
String quickjsNgPackageAssetUrl(String assetPath) {
  return Uri.base.resolve('assets/packages/quickjs/$assetPath').toString();
}

/// 注入 [quickjs_web.js] 并返回挂在 `globalThis` 上的 [quickjsNgWeb]。
Future<QuickjsWebHost> loadQuickjsWebHost() async {
  if (_JSObjectStatic.hasOwn(_globalThis, 'quickjsNgWeb'.toJS)) {
    return _quickjsNgWeb;
  }

  // web 插件注册阶段只是预加载；真正 create 时仍要确保脚本已注册全局对象。
  final scriptUrl = quickjsNgPackageAssetUrl('assets/web/quickjs_web.js');
  final completer = Completer<void>();
  final script = web.document.createElement('script') as web.HTMLScriptElement;
  script.src = scriptUrl;
  script.async = true;
  script.addEventListener('load', ((web.Event _) => completer.complete()).toJS);
  script.addEventListener(
    'error',
    ((web.Event _) => completer.completeError(
      StateError('Failed to load quickjs_web.js from $scriptUrl'),
    )).toJS,
  );
  web.document.head!.appendChild(script);
  await completer.future;

  if (!_JSObjectStatic.hasOwn(_globalThis, 'quickjsNgWeb'.toJS)) {
    throw StateError(
      'quickjsNgWeb was not registered — check browser console for JS errors',
    );
  }
  return _quickjsNgWeb;
}
