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
    List<String> permissions = const <String>[],
  }) async {
    final source = await (bundle ?? rootBundle).loadString(path);
    return singleFile(
      id: id,
      version: version,
      source: source,
      entryName: entryName,
      permissions: permissions,
    );
  }

  static QuickjsPlugin singleFile({
    required String id,
    required String version,
    required String source,
    String entryName = 'page',
    List<String> permissions = const <String>[],
  }) {
    final pageSpecifier = '$id/$entryName';
    final adapterSpecifier = '$id/main';
    return QuickjsPlugin(
      manifest: QuickjsPluginManifest(
        id: id,
        version: version,
        entry: adapterSpecifier,
        exports: const <String>['render', 'dispatch', 'lifecycle'],
        init: 'init',
        permissions: permissions,
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

export function lifecycle(state, event, props) {
  if (typeof page.lifecycle !== 'function') {
    return state;
  }
  return page.lifecycle(state, event, props);
}
''';
  }
}
