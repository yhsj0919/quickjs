import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui_webview/src/quickjs_ui_webview_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a previous document response cannot resolve a new request', () async {
    final engine = await JsEngine.create();
    addTearDown(engine.dispose);
    await engine.evalRaw('''
globalThis.window = globalThis;
window.TestChannel = {postMessage() {}};
globalThis.resolved = null;
globalThis.Promise = class { constructor(executor) { executor(value => resolved = value, () => {}); } };
''');
    await engine.evalRaw(webViewPageBridgeSource('TestChannel'));
    await engine.evalRaw('''
globalThis.oldDocument = window.__lemonWebView.documentId;
window.__lemonWebView.callHost('test', null);
delete window.__lemonWebView;
''');
    await engine.evalRaw(webViewPageBridgeSource('TestChannel'));
    expect(
      await engine.evalRaw('''
window.__lemonWebView.callHost('test', null);
window.__lemonWebView.resolveHostCall({documentId: oldDocument, id: 'page-1', result: 'old'});
JSON.stringify([resolved, oldDocument !== window.__lemonWebView.documentId]);
'''),
      '[null,true]',
    );
    expect(
      await engine.evalRaw('''
window.__lemonWebView.resolveHostCall({documentId: window.__lemonWebView.documentId, id: 'page-1', result: 'new'});
JSON.stringify(resolved);
'''),
      '"new"',
    );
  });
  test(
    'observed rules do not observe their own writes and can be replaced',
    () async {
      final engine = await JsEngine.create();
      addTearDown(engine.dispose);
      await engine.evalRaw('''
globalThis.window = globalThis;
window.TestChannel = {postMessage() {}};
globalThis.jobs = [];
globalThis.setTimeout = callback => jobs.push(callback);
globalThis.writes = 0;
globalThis.observer = null;
globalThis.element = {set textContent(value) {
  writes++;
  if (observer?.connected) observer.callback();
}};
globalThis.document = {documentElement: {}, querySelectorAll() { return [element]; }};
globalThis.MutationObserver = class {
  constructor(callback) { this.callback = callback; observer = this; }
  observe() { this.connected = true; }
  disconnect() { this.connected = false; }
};
''');
      await engine.evalRaw(webViewPageBridgeSource('TestChannel'));
      expect(
        await engine.evalRaw('''
const rule = {observe: true, path: [{selector: 'div'}], operations: [{action: 'setText', value: 'A'}]};
window.__lemonWebView.setConfiguredRules([rule]);
JSON.stringify([writes, jobs.length, observer.connected]);
'''),
        '[1,0,true]',
      );
      expect(
        await engine.evalRaw('''
observer.callback();
jobs.shift()();
JSON.stringify([writes, jobs.length]);
'''),
        '[2,0]',
      );
      expect(
        await engine.evalRaw('''
window.__lemonWebView.setConfiguredRules([{...rule, operations: [{action: 'setText', value: 'B'}]}]);
observer.callback(); jobs.shift()();
JSON.stringify([writes, jobs.length]);
'''),
        '[4,0]',
      );
      expect(
        await engine.evalRaw('''
window.__lemonWebView.setConfiguredRules(null);
JSON.stringify([writes, observer.connected]);
'''),
        '[4,false]',
      );
    },
  );
}
