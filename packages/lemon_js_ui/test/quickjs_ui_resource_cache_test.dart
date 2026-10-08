import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'disabled cache bypasses network responses and asset bundle cache',
    () async {
      final cache = JsUiResourceCache(maxAge: Duration.zero);
      final requests = <JsUiNetworkRequest>[];
      Future<JsUiNetworkResponse> fetch(JsUiNetworkRequest request) async {
        requests.add(request);
        return const JsUiNetworkResponse(
          statusCode: 200,
          body: 'export default {};',
          headers: {'etag': 'v1'},
        );
      }

      final url = Uri.parse('https://example.com/main.mjs');
      await cache.loadNetwork(url: url, fetch: fetch);
      await cache.loadNetwork(url: url, fetch: fetch);
      expect(
        requests.every((r) => !r.headers.containsKey('if-none-match')),
        isTrue,
      );
      expect(requests[0].uri, isNot(requests[1].uri));
      final bundle = _CountingAssetBundle(_pageSources());
      await cache.loadAsset(path: 'pages/a.mjs', bundle: bundle);
      expect(bundle.cacheFlags['pages/a.mjs'], [false]);
    },
  );

  test('invalidate removes response-only cache entries', () async {
    final cache = JsUiResourceCache();
    final requests = <JsUiNetworkRequest>[];
    Future<JsUiNetworkResponse> fetch(JsUiNetworkRequest request) async {
      requests.add(request);
      return const JsUiNetworkResponse(
        statusCode: 200,
        body: 'export default {};',
        headers: {'etag': 'v1'},
      );
    }

    final url = Uri.parse('https://example.com/main.mjs');
    await cache.loadNetwork(
      url: url,
      fetch: fetch,
      uncachedResources: {'other.mjs'},
    );
    cache.invalidate(url.toString());
    await cache.loadNetwork(
      url: url,
      fetch: fetch,
      uncachedResources: {'other.mjs'},
    );
    expect(requests.last.headers.containsKey('if-none-match'), isFalse);
  });

  test('asset cache reuses values and coalesces concurrent loads', () async {
    final bundle = _CountingAssetBundle(_pageSources());
    final cache = JsUiResourceCache();
    final results = await Future.wait(<Future<Object>>[
      cache.loadAsset(path: 'pages/a.mjs', bundle: bundle),
      cache.loadAsset(path: 'pages/a.mjs', bundle: bundle),
    ]);

    expect(identical(results.first, results.last), isTrue);
    expect(bundle.loads['pages/a.mjs'], 1);
  });

  test('asset cache evicts least recently used entries', () async {
    final bundle = _CountingAssetBundle(_pageSources());
    final cache = JsUiResourceCache(maxEntries: 1);
    await cache.loadAsset(path: 'pages/a.mjs', bundle: bundle);
    await cache.loadAsset(path: 'pages/b.mjs', bundle: bundle);
    await cache.loadAsset(path: 'pages/a.mjs', bundle: bundle);

    expect(cache.length, 1);
    expect(bundle.loads['pages/a.mjs'], 2);
  });

  test('oversized entries and expired entries are reloaded', () async {
    final bundle = _CountingAssetBundle(_pageSources());
    final tooSmall = JsUiResourceCache(maxBytes: 1);
    await tooSmall.loadAsset(path: 'pages/a.mjs', bundle: bundle);
    await tooSmall.loadAsset(path: 'pages/a.mjs', bundle: bundle);
    expect(tooSmall.length, 0);
    expect(bundle.loads['pages/a.mjs'], 2);

    final expiring = JsUiResourceCache(maxAge: const Duration(milliseconds: 1));
    await expiring.loadAsset(path: 'pages/b.mjs', bundle: bundle);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await expiring.loadAsset(path: 'pages/b.mjs', bundle: bundle);
    expect(bundle.loads['pages/b.mjs'], 2);
  });

  test('invalidate removes matching resource variants', () async {
    final bundle = _CountingAssetBundle(_pageSources());
    final cache = JsUiResourceCache();
    await cache.loadAsset(path: 'pages/a.mjs', bundle: bundle);
    cache.invalidate('pages/a.mjs');
    await cache.loadAsset(path: 'pages/a.mjs', bundle: bundle);

    expect(bundle.loads['pages/a.mjs'], 2);
  });

  test(
    'cache can be disabled and force refresh discards an old entry',
    () async {
      final bundle = _CountingAssetBundle(_pageSources());
      final cache = JsUiResourceCache();
      await cache.loadAsset(path: 'pages/a.mjs', bundle: bundle);
      await cache.loadAsset(
        path: 'pages/a.mjs',
        bundle: bundle,
        cacheEnabled: false,
      );
      await cache.loadAsset(path: 'pages/a.mjs', bundle: bundle);
      await cache.loadAsset(
        path: 'pages/a.mjs',
        bundle: bundle,
        forceRefresh: true,
      );
      await cache.loadAsset(path: 'pages/a.mjs', bundle: bundle);

      expect(bundle.loads['pages/a.mjs'], 4);
      expect(bundle.cacheFlags['pages/a.mjs'], <bool>[
        true,
        false,
        true,
        false,
      ]);
    },
  );

  test('uncached network module still revalidates other modules', () async {
    final requests = <JsUiNetworkRequest>[];
    final cache = JsUiResourceCache();
    final url = Uri.parse('https://example.com/ui/pages/main.mjs');
    Future<JsUiNetworkResponse> fetch(JsUiNetworkRequest request) async {
      requests.add(request);
      if (request.uri.path.endsWith('/main.mjs')) {
        if (request.headers['if-none-match'] == '"main-v1"') {
          return const JsUiNetworkResponse(body: '', statusCode: 304);
        }
        return const JsUiNetworkResponse(
          body: "import './live.mjs'; export default 1;",
          headers: <String, String>{'etag': '"main-v1"'},
        );
      }
      return const JsUiNetworkResponse(
        body: 'export const live = true;',
        headers: <String, String>{'etag': '"live-v1"'},
      );
    }

    await cache.loadNetwork(
      url: url,
      fetch: fetch,
      uncachedResources: const <String>{'pages/live.mjs'},
    );
    await cache.loadNetwork(
      url: url,
      fetch: fetch,
      uncachedResources: const <String>{'pages/live.mjs'},
    );

    expect(requests, hasLength(4));
    expect(requests[2].headers['if-none-match'], '"main-v1"');
    expect(requests[3].headers, isNot(contains('if-none-match')));
  });

  test('asset exclusion bypasses only the selected text file', () async {
    final bundle = _CountingAssetBundle(const <String, String>{
      'pages/main.mjs': "import './live.mjs'; export default 1;",
      'pages/live.mjs': 'export const live = true;',
    });
    final cache = JsUiResourceCache();
    for (var index = 0; index < 2; index += 1) {
      await cache.loadAsset(
        path: 'pages/main.mjs',
        bundle: bundle,
        uncachedResources: const <String>{'pages/live.mjs'},
      );
    }

    expect(bundle.cacheFlags['pages/main.mjs'], <bool>[true, true]);
    expect(bundle.cacheFlags['pages/live.mjs'], <bool>[false, false]);
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
  final Map<String, List<bool>> cacheFlags = <String, List<bool>>{};

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    loads[key] = (loads[key] ?? 0) + 1;
    cacheFlags.putIfAbsent(key, () => <bool>[]).add(cache);
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
