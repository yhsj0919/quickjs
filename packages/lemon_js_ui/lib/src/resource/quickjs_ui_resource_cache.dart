import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:lemon_js/lemon_js.dart';

import 'quickjs_ui_bundle.dart';
import 'quickjs_ui_network_loader.dart';

/// Bounded cache for parsed dynamic-UI bundles.
///
/// The cache owns only JavaScript module text and [JsPlugin] descriptors.
/// It never retains a QuickJS Context, page state, rendered widgets, or image
/// bytes; images remain governed by Flutter's ImageCache or an application
/// media cache. TTL, byte capacity and entry capacity are independent bounds.
/// Expired entries are removed lazily, and capacity eviction uses LRU order.
/// Failed loads and entries larger than [maxBytes] are never cached.
final class JsUiResourceCache {
  /// Creates an LRU cache with independent age, byte, and entry limits.
  JsUiResourceCache({
    this.maxAge = const Duration(minutes: 10),
    this.maxBytes = 16 * 1024 * 1024,
    this.maxEntries = 64,
  }) : assert(!maxAge.isNegative),
       assert(maxBytes >= 0),
       assert(maxEntries >= 0);

  /// Default process-wide cache used by JsUiView resource constructors.
  static final JsUiResourceCache shared = JsUiResourceCache();

  /// Maximum age of an entry before lazy expiration.
  final Duration maxAge;

  /// Maximum estimated UTF-8 bytes retained by the cache.
  final int maxBytes;

  /// Maximum number of retained plugins.
  final int maxEntries;
  final LinkedHashMap<String, _ResourceCacheEntry> _entries =
      LinkedHashMap<String, _ResourceCacheEntry>();
  final Map<String, Future<JsPlugin>> _pending = <String, Future<JsPlugin>>{};
  int _totalBytes = 0;

  /// Number of completed entries currently retained.
  int get length => _entries.length;

  /// Estimated bytes currently retained.
  int get totalBytes => _totalBytes;

  /// Whether all cache limits permit entries to be retained.
  bool get isEnabled =>
      maxAge > Duration.zero && maxBytes > 0 && maxEntries > 0;

  /// Loads and caches a plugin recursively sourced from Flutter assets.
  Future<JsPlugin> loadAsset({
    required String path,
    String? bundleRoot,
    AssetBundle? bundle,
  }) {
    final assetBundle = bundle ?? rootBundle;
    final key = 'asset:${identityHashCode(assetBundle)}:$bundleRoot:$path';
    return _load(
      key,
      () async => (await JsUiBundle.asset(
        path: path,
        bundleRoot: bundleRoot,
        bundle: assetBundle,
      )).toPlugin(),
    );
  }

  /// Loads and caches a plugin recursively sourced from local files.
  Future<JsPlugin> loadFile({required String path, String? bundleRoot}) {
    final key = 'file:$bundleRoot:$path';
    return _load(
      key,
      () async => (await JsUiBundle.file(
        path: path,
        bundleRoot: bundleRoot,
      )).toPlugin(),
    );
  }

  /// Loads and caches a plugin recursively sourced over the network.
  Future<JsPlugin> loadNetwork({
    required Uri url,
    Uri? bundleRoot,
    JsUiNetworkFetch? fetch,
    JsUiNetworkLogHandler? onLog,
  }) {
    final key = 'network:${identityHashCode(fetch)}:$bundleRoot:$url';
    return _load(
      key,
      () async => (await JsUiNetworkLoader(
        fetch: fetch,
        onLog: onLog,
      ).load(url: url, bundleRoot: bundleRoot)).toPlugin(),
    );
  }

  /// Removes every cached variant whose source path or URL matches [resource].
  /// Active pages are unaffected because they already own their plugin value.
  void invalidate(String resource) {
    final keys = _entries.keys
        .where((key) => key.endsWith(':$resource'))
        .toList(growable: false);
    for (final key in keys) {
      _remove(key);
    }
  }

  /// Removes all completed entries while leaving active pages untouched.
  void clear() {
    _entries.clear();
    _totalBytes = 0;
  }

  Future<JsPlugin> _load(String key, Future<JsPlugin> Function() loader) {
    if (!isEnabled) return loader();
    final now = DateTime.now();
    final cached = _entries.remove(key);
    if (cached != null) {
      _totalBytes -= cached.sizeBytes;
      if (now.difference(cached.createdAt) <= maxAge) {
        _entries[key] = cached;
        _totalBytes += cached.sizeBytes;
        return Future<JsPlugin>.value(cached.plugin);
      }
    }
    final pending = _pending[key];
    if (pending != null) return pending;
    final future = loader()
        .then((plugin) {
          final size = _pluginSize(plugin);
          if (size <= maxBytes) {
            _entries[key] = _ResourceCacheEntry(
              plugin: plugin,
              sizeBytes: size,
              createdAt: DateTime.now(),
            );
            _totalBytes += size;
            _evict();
          }
          return plugin;
        })
        .whenComplete(() {
          // Returning Map.remove's Future here would make whenComplete await
          // the same in-flight operation and create a self-wait cycle.
          _pending.remove(key);
        });
    _pending[key] = future;
    return future;
  }

  void _evict() {
    while (_entries.length > maxEntries || _totalBytes > maxBytes) {
      _remove(_entries.keys.first);
    }
  }

  void _remove(String key) {
    final removed = _entries.remove(key);
    if (removed != null) _totalBytes -= removed.sizeBytes;
  }
}

final class _ResourceCacheEntry {
  const _ResourceCacheEntry({
    required this.plugin,
    required this.sizeBytes,
    required this.createdAt,
  });

  final JsPlugin plugin;
  final int sizeBytes;
  final DateTime createdAt;
}

int _pluginSize(JsPlugin plugin) {
  var bytes =
      utf8.encode(plugin.manifest.id).length +
      utf8.encode(plugin.manifest.version).length +
      utf8.encode(plugin.manifest.entry).length;
  for (final module in plugin.modules) {
    bytes += utf8.encode(module.name).length;
    final source = module.source;
    if (source != null) bytes += utf8.encode(source).length;
  }
  return bytes;
}
