import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('globalThis')
external JSObject get _globalThis;

@JS('Object')
extension type _JSObjectStatic(JSObject _) implements JSObject {
  external static bool hasOwn(JSObject o, JSString prop);
}

@JS('quickjsNgWeb')
extension type QuickjsWebHost(JSObject _) implements JSObject {
  external JSPromise<JSString> ensureInitialized(
    JSString wasmUrl,
    JSString bridgeModuleUrl,
    JSString workerScriptUrl,
  );
  external JSString quickjsVersion();
  external JSPromise<JSString> evalCode(JSString code, [JSNumber? timeoutMs]);
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

/// Package asset URL for Flutter web.
String quickjsNgPackageAssetUrl(String assetPath) {
  return Uri.base.resolve('assets/packages/quickjs/$assetPath').toString();
}

/// Injects [quickjs_web.js] and returns [quickjsNgWeb] on `globalThis`.
Future<QuickjsWebHost> loadQuickjsWebHost() async {
  if (_JSObjectStatic.hasOwn(_globalThis, 'quickjsNgWeb'.toJS)) {
    return _quickjsNgWeb;
  }

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
