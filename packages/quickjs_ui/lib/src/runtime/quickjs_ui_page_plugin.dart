import 'package:flutter/services.dart';
import 'package:quickjs/quickjs.dart';

/// Builds QuickJS plugins from `export default Page(...)` UI modules.
final class QuickjsUiPagePlugin {
  const QuickjsUiPagePlugin._();

  static QuickjsPlugin asset({
    required String id,
    required String path,
    String version = '0.1.0',
    AssetBundle? bundle,
    String entryName = 'page',
    List<String> permissions = const <String>[],
  }) {
    final pageSpecifier = '$id/$entryName';
    return _plugin(
      id: id,
      version: version,
      pageSpecifier: pageSpecifier,
      pageModule: QuickjsPluginModule.asset(
        specifier: pageSpecifier,
        assetKey: path,
        bundle: bundle,
      ),
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
    return _plugin(
      id: id,
      version: version,
      pageSpecifier: pageSpecifier,
      pageModule: QuickjsPluginModule(specifier: pageSpecifier, source: source),
      entryName: entryName,
      permissions: permissions,
    );
  }

  static QuickjsPlugin _plugin({
    required String id,
    required String version,
    required String pageSpecifier,
    required QuickjsPluginModule pageModule,
    required String entryName,
    required List<String> permissions,
  }) {
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
          'bootstrap',
          'mutate',
          'poll',
        ],
        permissions: permissions,
      ),
      modules: <QuickjsPluginModule>[
        pageModule,
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

// Initial page startup crosses the Dart/worker/QuickJS boundary only once.
// Keep the individual exports below for updates after the first render.
export async function bootstrap(props) {
  requireRuntimeMethod('capabilities');
  requireRuntimeMethod('mount');
  requireRuntimeMethod('commit');
  const runtimeCapabilities = page.capabilities();
  const snapshot = await page.mount(props);
  const committed = await page.commit();
  return {
    capabilities: runtimeCapabilities,
    snapshot,
    commit: committed
  };
}

// Runs one complete state mutation without returning to Dart between the
// handler, state snapshot and schema commit.
export async function mutate(operation, payload, render = true) {
  let changed = false;
  switch (operation) {
    case 'finalize':
      requireRuntimeMethod('snapshot');
      requireRuntimeMethod('commit');
      return {
        changed: true,
        snapshot: page.snapshot(),
        commit: page.commit()
      };
    case 'dispatch': {
      requireRuntimeMethod('handleEvent');
      const events = Array.isArray(payload) ? payload : [payload];
      for (const event of events) {
        const result = await page.handleEvent(event);
        changed = result?.changed === true || result === true || changed;
      }
      break;
    }
    case 'setState': {
      requireRuntimeMethod('setState');
      const result = await page.setState(payload);
      changed = result?.changed === true || result === true;
      break;
    }
    case 'lifecycle': {
      requireRuntimeMethod('lifecycle');
      const result = await page.lifecycle(payload);
      changed = result?.changed === true || result === true;
      break;
    }
    default:
      throw new TypeError('quickjs_ui unknown mutation operation: ' + operation);
  }
  if (!changed) {
    return { changed: false };
  }
  // Large event bursts are sent in bounded chunks. Intermediate chunks update
  // JS-owned state only; one final call materializes the Dart state and schema.
  if (operation === 'dispatch' && !render) {
    return { changed: true };
  }
  requireRuntimeMethod('snapshot');
  const snapshot = page.snapshot();
  let committed = null;
  if (render) {
    requireRuntimeMethod('commit');
    committed = page.commit();
  }
  return {
    changed: true,
    snapshot,
    commit: committed
  };
}

// Polling compares the JS-owned state version before materializing data for
// Dart. Idle timer ticks therefore return only a small unchanged marker.
export function poll(lastVersion) {
  requireRuntimeMethod('snapshot');
  const snapshot = page.snapshot();
  if (snapshot?.version === lastVersion) {
    return { changed: false, version: lastVersion };
  }
  requireRuntimeMethod('commit');
  return {
    changed: true,
    snapshot,
    commit: page.commit()
  };
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
