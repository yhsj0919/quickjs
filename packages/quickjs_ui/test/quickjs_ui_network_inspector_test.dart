import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

void main() {
  group('quickjs_ui network inspector', () {
    test('journal merges bundle request lifecycle into one record', () async {
      final journal = QuickjsUiNetworkJournal();
      final loader = QuickjsUiNetworkLoader(
        onLog: journal.handleLogEvent,
        fetch: (request) async {
          if (request.headers['if-none-match'] == '"v1"') {
            return const QuickjsUiNetworkResponse(
              body: '',
              statusCode: HttpStatus.notModified,
            );
          }
          return const QuickjsUiNetworkResponse(
            body: 'export default 1;',
            headers: <String, String>{'etag': '"v1"'},
          );
        },
      );

      final url = Uri.parse('https://example.com/ui/pages/main.mjs');
      await loader.load(url: url);
      await loader.load(url: url);

      expect(journal.records, hasLength(2));
      expect(
        journal.records.first.phase,
        QuickjsUiNetworkRecordPhase.completed,
      );
      expect(journal.records.first.bodyBytes, greaterThan(0));
      expect(journal.records.last.phase, QuickjsUiNetworkRecordPhase.cacheHit);
      expect(journal.records.last.fromCache, isTrue);
      expect(journal.records.last.durationMs, isNotNull);
    });

    test('journal records host network requests', () async {
      final journal = QuickjsUiNetworkJournal();
      final handlers = instrumentHostNetworkLogging(
        QuickjsUiHostApiHandlers(
          onNetworkRequest: (request) async {
            return <String, Object?>{'statusCode': 200, 'body': '{"ok":true}'};
          },
        ),
        journal,
      );

      final result = await handlers.onNetworkRequest!(<String, Object?>{
        'method': 'post',
        'url': 'https://api.example.com/profile',
      });

      expect(result, isA<Map>());
      expect(journal.records, hasLength(1));
      final record = journal.records.single;
      expect(record.source, QuickjsUiNetworkSource.host);
      expect(record.method, 'POST');
      expect(record.uri.toString(), 'https://api.example.com/profile');
      expect(record.phase, QuickjsUiNetworkRecordPhase.completed);
      expect(record.statusCode, 200);
      expect(record.bodyBytes, greaterThan(0));
    });

    test('inspector snapshot includes network records', () {
      final inspector = QuickjsUiInspector();
      inspector.networkJournal.handleLogEvent(
        QuickjsUiNetworkLogEvent(
          id: 'bundle-1',
          type: 'network.request',
          uri: Uri.parse('https://example.com/ui/pages/main.mjs'),
          method: 'GET',
        ),
      );
      inspector.networkJournal.handleLogEvent(
        QuickjsUiNetworkLogEvent(
          id: 'bundle-1',
          type: 'network.cacheStore',
          uri: Uri.parse('https://example.com/ui/pages/main.mjs'),
          method: 'GET',
          statusCode: 200,
          durationMs: 12,
          bodyBytes: 128,
        ),
      );

      final controller = QuickjsUiController(inspector: inspector);
      addTearDown(controller.dispose);
      final snapshot = controller.exportPageSnapshotMap();
      expect(snapshot['network'], isA<List>());
      expect((snapshot['network'] as List), hasLength(1));
    });

    test('network package force refresh bypasses conditional header', () async {
      final requests = <QuickjsUiNetworkRequest>[];
      var sourceVersion = 1;
      final loader = QuickjsUiNetworkLoader(
        cacheBuster: (_) => 'dev',
        fetch: (request) async {
          requests.add(request);
          final path = request.uri.path;
          if (path.endsWith('/manifest.json')) {
            return const QuickjsUiNetworkResponse(
              body: '''
{
  "schemaVersion": 1,
  "id": "quickjs_ui.test.network_package",
  "version": "1.0.0",
  "entry": "main.mjs",
  "modules": {
    "main.mjs": {}
  }
}
''',
              headers: <String, String>{'etag': '"manifest-v1"'},
            );
          }
          if (path.endsWith('/main.mjs')) {
            return QuickjsUiNetworkResponse(
              body: 'export const version = $sourceVersion;',
              headers: <String, String>{'etag': '"main-v$sourceVersion"'},
            );
          }
          return const QuickjsUiNetworkResponse(body: '', statusCode: 404);
        },
      );

      await loader.loadPackage(
        root: Uri.parse('https://example.com/ui/package/'),
      );
      sourceVersion = 2;
      final refreshed = await loader.loadPackageWithRefresh(
        root: Uri.parse('https://example.com/ui/package/'),
        refreshMode: QuickjsUiNetworkRefreshMode.force,
      );

      expect(refreshed.modules['main.mjs'], contains('2'));
      expect(requests[2].headers, isNot(contains('if-none-match')));
      expect(
        requests[2].uri.queryParameters,
        containsPair('_quickjs_ui_cache_bust', 'dev'),
      );
      expect(requests[3].headers, isNot(contains('if-none-match')));
    });

    test(
      'network package stale-while-revalidate returns cached body',
      () async {
        final requests = <QuickjsUiNetworkRequest>[];
        var sourceVersion = 1;
        final loader = QuickjsUiNetworkLoader(
          fetch: (request) async {
            requests.add(request);
            final path = request.uri.path;
            if (path.endsWith('/manifest.json')) {
              if (request.headers['if-none-match'] == '"manifest-v1"') {
                return const QuickjsUiNetworkResponse(
                  body: '',
                  statusCode: HttpStatus.notModified,
                );
              }
              return const QuickjsUiNetworkResponse(
                body: '''
{
  "schemaVersion": 1,
  "id": "quickjs_ui.test.network_package",
  "version": "1.0.0",
  "entry": "main.mjs",
  "modules": {
    "main.mjs": {}
  }
}
''',
                headers: <String, String>{'etag': '"manifest-v1"'},
              );
            }
            if (path.endsWith('/main.mjs')) {
              return QuickjsUiNetworkResponse(
                body: 'export const version = $sourceVersion;',
                headers: <String, String>{'etag': '"main-v$sourceVersion"'},
              );
            }
            return const QuickjsUiNetworkResponse(body: '', statusCode: 404);
          },
        );

        await loader.loadPackage(
          root: Uri.parse('https://example.com/ui/package/'),
        );
        sourceVersion = 2;
        final stale = await loader.loadPackageWithRefresh(
          root: Uri.parse('https://example.com/ui/package/'),
          refreshMode: QuickjsUiNetworkRefreshMode.staleWhileRevalidate,
        );

        expect(stale.modules['main.mjs'], contains('1'));
        await Future<void>.delayed(Duration.zero);
        expect(requests.length, greaterThan(2));
        expect(
          requests.last.headers,
          containsPair('if-none-match', '"main-v1"'),
        );
      },
    );

    test(
      'network package reuses cache store across loader instances',
      () async {
        final store = QuickjsUiMemoryNetworkCacheStore();
        final requests = <QuickjsUiNetworkRequest>[];
        QuickjsUiNetworkLoader newLoader() {
          return QuickjsUiNetworkLoader(
            cacheStore: store,
            fetch: (request) async {
              requests.add(request);
              final path = request.uri.path;
              if (request.headers['if-none-match'] == '"v1"') {
                return const QuickjsUiNetworkResponse(
                  body: '',
                  statusCode: HttpStatus.notModified,
                );
              }
              if (path.endsWith('/manifest.json')) {
                return const QuickjsUiNetworkResponse(
                  body: '''
{
  "schemaVersion": 1,
  "id": "quickjs_ui.test.cached_package",
  "version": "1.0.0",
  "entry": "main.mjs",
  "modules": {
    "main.mjs": {}
  }
}
''',
                  headers: <String, String>{'etag': '"v1"'},
                );
              }
              if (path.endsWith('/main.mjs')) {
                return const QuickjsUiNetworkResponse(
                  body: 'export const cached = true;',
                  headers: <String, String>{'etag': '"v1"'},
                );
              }
              return const QuickjsUiNetworkResponse(body: '', statusCode: 404);
            },
          );
        }

        final root = Uri.parse('https://example.com/ui/package/');
        await newLoader().loadPackage(root: root);
        final bundle = await newLoader().loadPackage(root: root);

        expect(bundle.modules['main.mjs'], contains('cached = true'));
        expect(requests[2].headers, containsPair('if-none-match', '"v1"'));
        expect(requests[3].headers, containsPair('if-none-match', '"v1"'));
      },
    );
  });
}
