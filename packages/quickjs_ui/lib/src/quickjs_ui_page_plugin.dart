import 'package:flutter/services.dart';
import 'package:quickjs/quickjs.dart';

/// Builds QuickJS plugins from `export default Page(...)` UI modules.
final class QuickjsUiPagePlugin {
  const QuickjsUiPagePlugin._();

  static Future<QuickjsPlugin> asset({
    required String id,
    required String path,
    String version = '0.1.0',
    AssetBundle? bundle,
    String entryName = 'page',
  }) async {
    final source = await (bundle ?? rootBundle).loadString(path);
    return singleFile(
      id: id,
      version: version,
      source: source,
      entryName: entryName,
    );
  }

  static QuickjsPlugin singleFile({
    required String id,
    required String version,
    required String source,
    String entryName = 'page',
  }) {
    final pageSpecifier = '$id/$entryName';
    final adapterSpecifier = '$id/main';
    return QuickjsPlugin(
      manifest: QuickjsPluginManifest(
        id: id,
        version: version,
        entry: adapterSpecifier,
        exports: const <String>['render', 'dispatch'],
        init: 'init',
      ),
      modules: <QuickjsPluginModule>[
        QuickjsPluginModule(specifier: pageSpecifier, source: source),
        QuickjsPluginModule(
          specifier: adapterSpecifier,
          source: adapterSource(pageSpecifier),
        ),
      ],
    );
  }

  static String adapterSource(String pageSpecifier) {
    return '''
import page from '$pageSpecifier';

export function init(props) {
  return page.init(props);
}

export function render(state, props) {
  return page.render(state, props);
}

export function dispatch(state, event, props) {
  return page.dispatch(state, event, props);
}
''';
  }
}
