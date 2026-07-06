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

  /// Builds a page plugin from page source embedded in Dart at build time.
  ///
  /// This is the synchronous counterpart of [asset].
  static QuickjsPlugin compiledAsset({
    required String id,
    required String source,
    String version = '0.1.0',
    String entryName = 'page',
    List<String> permissions = const <String>[],
  }) {
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
        exports: const <String>[
          'mount',
          'handleEvent',
          'commit',
          'setState',
          'lifecycle',
          'snapshot',
          'capabilities',
          'dispose',
        ],
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

function requireRuntimeMethod(name) {
  if (typeof page?.[name] !== 'function') {
    throw new Error(
      'quickjs_ui page runtime protocol mismatch: ' + name + ' is missing'
    );
  }
}

export function capabilities() {
  requireRuntimeMethod('capabilities');
  return page.capabilities();
}

export function mount(props) {
  requireRuntimeMethod('mount');
  return page.mount(props);
}

export function handleEvent(event) {
  requireRuntimeMethod('handleEvent');
  return page.handleEvent(event);
}

export function commit() {
  requireRuntimeMethod('commit');
  return page.commit();
}

export function setState(patch) {
  requireRuntimeMethod('setState');
  return page.setState(patch);
}

export function lifecycle(event) {
  requireRuntimeMethod('lifecycle');
  return page.lifecycle(event);
}

export function snapshot() {
  requireRuntimeMethod('snapshot');
  return page.snapshot();
}

export function dispose() {
  if (typeof page?.dispose === 'function') {
    return page.dispose();
  }
  return true;
}
''';
  }
}
