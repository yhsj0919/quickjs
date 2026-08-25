import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui/lemon_js_ui_session.dart';
import 'package:lemon_js_ui_webview/lemon_js_ui_webview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the stable quickjs_ui/webview module specifier', () {
    final plugin = JsUiWebViewPlugin();
    expect(jsUiWebViewModuleSpecifier, 'quickjs_ui/webview');
    expect(plugin.plugin.name, 'quickjs_ui:plugin:webview');
  });

  test('host instances own isolated plugin descriptors', () {
    final first = JsUiWebViewPlugin();
    final second = JsUiWebViewPlugin();

    expect(identical(first.plugin, second.plugin), isFalse);
  });

  test('omits optional WebView props instead of exporting undefined', () async {
    final plugin = JsUiWebViewPlugin();
    final session = JsUiSession();
    addTearDown(session.dispose);

    await session.loadPlugin(
      JsUiPagePlugin.source(
        id: 'quickjs_ui_webview_optional_props_test',
        version: '0.1.0',
        source: '''
import { Page } from 'quickjs_ui';
import { WebView, createWebBridge } from 'quickjs_ui/webview';

const bridge = createWebBridge('optional-props-test');
export default Page({
  build() {
    return WebView({
      bridge,
      url: 'https://example.com',
      frameScripts: ['globalThis.frameReady = true;']
    });
  }
});
''',
      ),
      features: plugin.plugin.features,
    );

    expect(session.node?.props['bridge'], isNull);
    expect(session.node?.props['rules'], isNull);
    expect(session.node?.props['frameScripts'], <String>[
      'globalThis.frameReady = true;',
    ]);
  });

  test('compiles fluent DOM rules into serializable WebView props', () async {
    final plugin = JsUiWebViewPlugin();
    final session = JsUiSession();
    addTearDown(session.dispose);

    await session.loadPlugin(
      JsUiPagePlugin.source(
        id: 'quickjs_ui_webview_dsl_test',
        version: '0.1.0',
        source: '''
import { Page } from 'quickjs_ui';
import { WebView, createWebBridge, dom, webRules } from 'quickjs_ui/webview';

const bridge = createWebBridge('isolated-test-bridge');

export default Page({
  build() {
    return WebView({
      bridge,
      html: '<main id="A"><section class="B"><p class="C">A</p></section></main>',
      rules: webRules(
        dom('#A').children('.B').find('.C').first()
          .replaceText('A', 'B')
          .attr('data-selected', 'true')
          .isolate({ fillViewport: true, removeOthers: true })
      )
    });
  }
});
''',
      ),
      features: plugin.plugin.features,
    );

    final node = session.node;
    expect(node?.type, 'WebView');
    expect(node?.props['bridgeId'], 'isolated-test-bridge');
    expect(node?.props['bridge'], isNull);
    final rules = node?.props['rules']! as List<Object?>;
    final rule = rules.single as Map<String, Object?>;
    final path = rule['path']! as List<Object?>;
    expect(path, hasLength(3));
    expect((path[1] as Map<String, Object?>)['relation'], 'child');
    expect((path[2] as Map<String, Object?>)['index'], 0);
    final operations = rule['operations']! as List<Object?>;
    expect(
      operations.map(
        (operation) => (operation as Map<String, Object?>)['action'],
      ),
      <String>['replaceText', 'setAttribute', 'isolate'],
    );
    expect(
      (operations.last as Map<String, Object?>)['options'],
      <String, Object?>{'fillViewport': true, 'removeOthers': true},
    );
  });
}
