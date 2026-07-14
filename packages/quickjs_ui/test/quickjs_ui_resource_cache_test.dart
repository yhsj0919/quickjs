import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asset cache reuses values and coalesces concurrent loads', () async {
    final bundle = _CountingAssetBundle(_pageSources());
    final cache = QuickjsUiResourceCache();
    final results = await Future.wait(<Future<Object>>[
      cache.loadAsset(path: 'pages/a.mjs', bundle: bundle),
      cache.loadAsset(path: 'pages/a.mjs', bundle: bundle),
    ]);

    expect(identical(results.first, results.last), isTrue);
    expect(bundle.loads['pages/a.mjs'], 1);
  });

  test('asset cache evicts least recently used entries', () async {
    final bundle = _CountingAssetBundle(_pageSources());
    final cache = QuickjsUiResourceCache(maxEntries: 1);
    await cache.loadAsset(path: 'pages/a.mjs', bundle: bundle);
    await cache.loadAsset(path: 'pages/b.mjs', bundle: bundle);
    await cache.loadAsset(path: 'pages/a.mjs', bundle: bundle);

    expect(cache.length, 1);
    expect(bundle.loads['pages/a.mjs'], 2);
  });

  test('oversized entries and expired entries are reloaded', () async {
    final bundle = _CountingAssetBundle(_pageSources());
    final tooSmall = QuickjsUiResourceCache(maxBytes: 1);
    await tooSmall.loadAsset(path: 'pages/a.mjs', bundle: bundle);
    await tooSmall.loadAsset(path: 'pages/a.mjs', bundle: bundle);
    expect(tooSmall.length, 0);
    expect(bundle.loads['pages/a.mjs'], 2);

    final expiring = QuickjsUiResourceCache(
      maxAge: const Duration(milliseconds: 1),
    );
    await expiring.loadAsset(path: 'pages/b.mjs', bundle: bundle);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await expiring.loadAsset(path: 'pages/b.mjs', bundle: bundle);
    expect(bundle.loads['pages/b.mjs'], 2);
  });

  test('invalidate removes matching resource variants', () async {
    final bundle = _CountingAssetBundle(_pageSources());
    final cache = QuickjsUiResourceCache();
    await cache.loadAsset(path: 'pages/a.mjs', bundle: bundle);
    cache.invalidate('pages/a.mjs');
    await cache.loadAsset(path: 'pages/a.mjs', bundle: bundle);

    expect(bundle.loads['pages/a.mjs'], 2);
  });
}

Map<String, String> _pageSources() => const <String, String>{
  'pages/a.mjs': 'export default { value: "a" };',
  'pages/b.mjs': 'export default { value: "b" };',
};

final class _CountingAssetBundle extends CachingAssetBundle {
  _CountingAssetBundle(this.sources);

  final Map<String, String> sources;
  final Map<String, int> loads = <String, int>{};

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    loads[key] = (loads[key] ?? 0) + 1;
    final source = sources[key];
    if (source == null) throw StateError('Missing asset: $key');
    return source;
  }

  @override
  Future<ByteData> load(String key) async {
    final source = sources[key];
    if (source == null) throw StateError('Missing asset: $key');
    final bytes = Uint8List.fromList(utf8.encode(source));
    return ByteData.sublistView(bytes);
  }
}
