import 'package:flutter/services.dart';
import 'package:lemon_js/lemon_js.dart';

/// Protocol exports provided by the generated JSUI page adapter module.
const List<String> jsUiPagePluginExports = <String>[
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
  'mutationChunk',
  'poll',
];

/// Builds QuickJS plugins from `export default Page(...)` UI modules.
final class JsUiPagePlugin {
  const JsUiPagePlugin._();

  /// Creates a page plugin from a JavaScript module in a Flutter asset.
  static JsPlugin asset({
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
      pageModule: JsPluginModule.asset(
        name: pageSpecifier,
        path: path,
        bundle: bundle,
      ),
      entryName: entryName,
      permissions: permissions,
    );
  }

  /// Creates a UI page plugin from inline JavaScript [source].
  static JsPlugin source({
    required String id,
    required String source,
    String version = '0.1.0',
    String entryName = 'page',
    List<String> permissions = const <String>[],
  }) {
    final pageSpecifier = '$id/$entryName';
    return _plugin(
      id: id,
      version: version,
      pageSpecifier: pageSpecifier,
      pageModule: JsPluginModule(name: pageSpecifier, source: source),
      entryName: entryName,
      permissions: permissions,
    );
  }

  static JsPlugin _plugin({
    required String id,
    required String version,
    required String pageSpecifier,
    required JsPluginModule pageModule,
    required String entryName,
    required List<String> permissions,
  }) {
    final adapterSpecifier = '$id/main';
    return JsPlugin(
      manifest: JsPluginManifest(
        id: id,
        version: version,
        entry: adapterSpecifier,
        exports: jsUiPagePluginExports,
        permissions: permissions,
      ),
      modules: <JsPluginModule>[
        pageModule,
        JsPluginModule(
          name: adapterSpecifier,
          source: adapterSource(pageSpecifier),
        ),
      ],
    );
  }

  /// Generates the adapter module for the page at [pageSpecifier].
  static String adapterSource(String pageSpecifier) {
    return '''
import page from '$pageSpecifier';

const mutationChunkSize = 64 * 1024;
const mutationNodeLimit = 4096;
const pendingMutations = new Map();
let nextMutationId = 1;

function transportMutation(result) {
  const json = JSON.stringify(result);
  if (
    json.length <= mutationChunkSize &&
    countMutationNodes(result, mutationNodeLimit) <= mutationNodeLimit
  ) {
    return result;
  }
  pendingMutations.clear();
  const id = String(nextMutationId++);
  pendingMutations.set(id, json);
  return {
    changed: result?.changed === true,
    chunked: true,
    transferId: id,
    chunkCount: Math.ceil(json.length / mutationChunkSize)
  };
}

function countMutationNodes(root, limit) {
  const pending = [root];
  const seen = new Set();
  let count = 0;
  while (pending.length > 0 && count <= limit) {
    const value = pending.pop();
    count += 1;
    if (value == null || typeof value !== 'object') continue;
    if (seen.has(value)) continue;
    seen.add(value);
    if (Array.isArray(value)) {
      for (const child of value) pending.push(child);
    } else {
      for (const key of Object.keys(value)) pending.push(value[key]);
    }
  }
  return count;
}

export function mutationChunk(id, index) {
  const json = pendingMutations.get(id);
  if (typeof json !== 'string') {
    throw new Error('quickjs_ui mutation transfer is missing: ' + id);
  }
  if (!Number.isInteger(index) || index < 0) {
    throw new TypeError('quickjs_ui mutation chunk index is invalid');
  }
  const chunkCount = Math.ceil(json.length / mutationChunkSize);
  if (index >= chunkCount) {
    throw new RangeError('quickjs_ui mutation chunk index is out of range');
  }
  const chunk = json.slice(index * mutationChunkSize, (index + 1) * mutationChunkSize);
  if (index + 1 === chunkCount) pendingMutations.delete(id);
  return chunk;
}

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
  return transportMutation({
    capabilities: runtimeCapabilities,
    snapshot,
    commit: committed
  });
}

// Runs one complete state mutation without returning to Dart between the
// handler, state snapshot and schema commit.
export async function mutate(operation, payload, render = true) {
  let changed = false;
  switch (operation) {
    case 'finalize':
      requireRuntimeMethod('snapshot');
      requireRuntimeMethod('commit');
      return transportMutation({
        changed: true,
        snapshot: page.snapshot(),
        commit: page.commit()
      });
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
  return transportMutation({
    changed: true,
    snapshot,
    commit: committed
  });
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
  return transportMutation({
    changed: true,
    snapshot,
    commit: page.commit()
  });
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
